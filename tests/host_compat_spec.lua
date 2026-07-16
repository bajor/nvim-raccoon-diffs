package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local h = require("tests.helpers")
local adapter = require("raccoon_inline_diff.host.raccoon")
local lifecycle = require("raccoon_inline_diff.lifecycle")
local renderer = require("raccoon_inline_diff.render")

local host = require("raccoon")
local host_diff = require("raccoon.diff")
local host_state = require("raccoon.state")
local host_commits = require("raccoon.commits")
local host_local = require("raccoon.localcommits")
local host_modules = {
  raccoon = host,
  diff = host_diff,
  state = host_state,
  commits = host_commits,
  localcommits = host_local,
}

local buffers = {}

local function buffer(lines, name)
  local value = vim.api.nvim_create_buf(false, true)
  buffers[#buffers + 1] = value
  vim.api.nvim_buf_set_lines(value, 0, -1, false, lines)
  if name then vim.api.nvim_buf_set_name(value, name) end
  return value
end

local function extmarks(buffer_value, namespace)
  return vim.api.nvim_buf_get_extmarks(buffer_value, namespace, 0, -1, { details = true, hl_name = true })
end

local function find_route(snapshots, route)
  for _, snapshot in ipairs(snapshots) do
    if snapshot.route == route then return snapshot end
  end
  return nil
end

h.test("pinned host capabilities load with and without the extension", function()
  local compatible, err = adapter.check_compatibility()
  h.equal(compatible, true, err)
  require("raccoon_inline_diff").setup({ enabled = false, diagnostics = "silent" })
  h.equal(package.loaded["raccoon"], host_modules.raccoon)
  h.equal(package.loaded["raccoon.diff"], host_modules.diff)
  h.equal(package.loaded["raccoon.state"], host_modules.state)
  h.equal(package.loaded["raccoon.commits"], host_modules.commits)
  h.equal(package.loaded["raccoon.localcommits"], host_modules.localcommits)
end)

h.test("flat PR additions receive oracle spans without changing host state", function()
  local root = "/tmp/raccoon-inline-host-compat"
  local target = buffer({ "new value" }, root .. "/sample.lua")
  local patch = "@@ -1,1 +1,1 @@\n-old value\n+new value\n"
  host_state.start({ clone_path = root })
  host_state.set_files({ { filename = "sample.lua", patch = patch } })
  host_diff.apply_highlights(target, patch)

  local host_namespace = vim.api.nvim_get_namespaces().raccoon_diff
  local lines_before = vim.api.nvim_buf_get_lines(target, 0, -1, false)
  local host_marks_before = extmarks(target, host_namespace)
  local coordinates_before = host_diff.parse_patch(patch)
  local snapshot = find_route(adapter.snapshots(), "flat_pr_additions")
  h.truthy(snapshot, "flat route snapshot missing")
  lifecycle._refresh(snapshot)
  vim.wait(200, function() return #extmarks(target, renderer.namespace()) > 0 end, 10)

  h.equal(#extmarks(target, renderer.namespace()), 1)
  h.deep_equal(vim.api.nvim_buf_get_lines(target, 0, -1, false), lines_before)
  h.deep_equal(extmarks(target, host_namespace), host_marks_before)
  h.deep_equal(host_diff.parse_patch(patch), coordinates_before)
  lifecycle.stop()
  h.equal(#extmarks(target, renderer.namespace()), 0)
  h.deep_equal(extmarks(target, host_namespace), host_marks_before)
  host_state.reset()
end)

h.test("commit grid and maximized routes use copied real-buffer state", function()
  local grid = buffer({ "old value", "new value" })
  local maximum = buffer({ "old value", "new value" })
  local namespace = vim.api.nvim_get_namespaces().raccoon_commits
  for _, target in ipairs({ grid, maximum }) do
    vim.api.nvim_buf_set_extmark(target, namespace, 0, 0, {
      line_hl_group = "RaccoonDelete",
      sign_text = "-",
    })
    vim.api.nvim_buf_set_extmark(target, namespace, 1, 0, {
      line_hl_group = "RaccoonAdd",
      sign_text = "+",
    })
  end
  local state = host_commits._get_state()
  state.active = true
  state.grid_bufs = { grid }
  state.maximize_buf = maximum
  state.select_generation = 8
  state.current_page = 1
  state.focus_target = "sidebar"
  local grid_marks = extmarks(grid, namespace)
  local max_marks = extmarks(maximum, namespace)
  local snapshots = adapter.snapshots()
  h.truthy(find_route(snapshots, "commit_grid"))
  h.truthy(find_route(snapshots, "commit_maximized"))
  h.deep_equal(extmarks(grid, namespace), grid_marks)
  h.deep_equal(extmarks(maximum, namespace), max_marks)
  state.active = false
  state.grid_bufs = {}
  state.maximize_buf = nil
end)

h.test("local Current changes preview is capability checked", function()
  local preview = buffer({ "old", "new" })
  local namespace = vim.api.nvim_get_namespaces().raccoon_local_commits
  vim.api.nvim_buf_set_extmark(preview, namespace, 0, 0, {
    line_hl_group = "RaccoonDelete",
    sign_text = "-",
  })
  vim.api.nvim_buf_set_extmark(preview, namespace, 1, 0, {
    line_hl_group = "RaccoonAdd",
    sign_text = "+",
  })
  local state = host_local._get_state()
  state.active = true
  state.grid_bufs = { preview }
  state.branch_commits = { { sha = nil, message = "Current changes" } }
  state.base_commits = {}
  state.selected_index = 1
  state.focus_target = "filetree"
  state.filetree_preview_path = "sample.lua"
  state.select_generation = 4
  state.preview_generation = 2
  local snapshot = find_route(adapter.snapshots(), "current_changes_preview")
  h.truthy(snapshot, "Current changes preview snapshot missing")
  h.equal(snapshot.records[1].kind, "deletion")
  h.equal(snapshot.records[2].kind, "addition")
  state.active = false
  state.grid_bufs = {}
  state.filetree_preview_path = nil
end)

h.test("missing private route capability fails closed", function()
  local original = package.loaded["raccoon.commits"]
  package.loaded["raccoon.commits"] = {}
  local ok, snapshots = pcall(adapter.snapshots)
  h.equal(ok, true)
  h.equal(find_route(snapshots, "commit_grid"), nil)
  package.loaded["raccoon.commits"] = original
end)

for _, target in ipairs(buffers) do
  if vim.api.nvim_buf_is_valid(target) then vim.api.nvim_buf_delete(target, { force = true }) end
end

h.run()
