package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local h = require("tests.helpers")
local adapter = require("raccoon_inline_diff.host.raccoon")
local config = require("raccoon_inline_diff.config")
local lifecycle = require("raccoon_inline_diff.lifecycle")
local renderer = require("raccoon_inline_diff.render")

package.preload["raccoon"] = package.preload["raccoon"] or function() return {} end

local created_buffers = {}

local function buffer(lines)
  local value = vim.api.nvim_create_buf(false, true)
  created_buffers[#created_buffers + 1] = value
  vim.api.nvim_buf_set_lines(value, 0, -1, false, lines)
  return value
end

local function marks(buffer_value, namespace)
  return vim.api.nvim_buf_get_extmarks(buffer_value, namespace, 0, -1, { details = true, hl_name = true })
end

local function wait_for_scheduled()
  vim.wait(100, function() return false end, 10)
end

h.test("configuration rejects invalid states", function()
  h.deep_equal(config.resolve(), { enabled = true, diagnostics = "warn" })
  h.deep_equal(config.resolve({ enabled = false, diagnostics = "silent" }), {
    enabled = false,
    diagnostics = "silent",
  })
  h.raises(function() config.resolve({ enabled = "yes" }) end, "must be a boolean")
  h.raises(function() config.resolve({ diagnostics = "debug" }) end, "must be silent, warn, or error")
  h.raises(function() config.resolve({ pairing = "smart" }) end, "unknown raccoon%-inline%-diff option")
end)

h.test("renderer applies exact combined byte ranges and preserves other namespaces", function()
  local target = buffer({ "a😀é" })
  local host_namespace = vim.api.nvim_create_namespace("raccoon_test_host")
  local unrelated_namespace = vim.api.nvim_create_namespace("raccoon_test_unrelated")
  vim.api.nvim_buf_set_extmark(target, host_namespace, 0, 0, { line_hl_group = "DiffAdd", sign_text = "+" })
  vim.api.nvim_buf_set_extmark(target, unrelated_namespace, 0, 0, { end_col = 1, hl_group = "Comment" })

  renderer.setup_highlights()
  local original_set_extmark = vim.api.nvim_buf_set_extmark
  local captured_options
  vim.api.nvim_buf_set_extmark = function(...)
    local arguments = { ... }
    captured_options = arguments[5]
    return original_set_extmark(...)
  end
  local applied, err = renderer.apply(target, {
    { row = 0, start_byte = 1, end_byte = 5, side = "addition" },
  })
  vim.api.nvim_buf_set_extmark = original_set_extmark
  h.equal(applied, true, err)
  local extension_marks = marks(target, renderer.namespace())
  h.equal(#extension_marks, 1)
  h.equal(extension_marks[1][2], 0)
  h.equal(extension_marks[1][3], 1)
  h.equal(extension_marks[1][4].end_col, 5)
  h.equal(extension_marks[1][4].hl_group, "RaccoonInlineDiffAddText")
  h.equal(captured_options.hl_mode, "combine")
  h.equal(#marks(target, host_namespace), 1)
  h.equal(#marks(target, unrelated_namespace), 1)

  renderer.apply(target, { { row = 0, start_byte = 1, end_byte = 5, side = "addition" } })
  h.equal(#marks(target, renderer.namespace()), 1, "reapplication must be idempotent")
  renderer.clear(target)
  h.equal(#marks(target, renderer.namespace()), 0)
  h.equal(#marks(target, host_namespace), 1)
  h.equal(#marks(target, unrelated_namespace), 1)
end)

h.test("renderer fails closed for invalid UTF-8 byte boundaries", function()
  local target = buffer({ "😀" })
  local applied = renderer.apply(target, {
    { row = 0, start_byte = 1, end_byte = 4, side = "addition" },
  })
  h.equal(applied, false)
  h.equal(#marks(target, renderer.namespace()), 0)
end)

h.test("renderer preserves user-defined highlights", function()
  vim.api.nvim_set_hl(0, "RaccoonInlineDiffAddText", { fg = "#abcdef", bg = "#102030" })
  renderer.setup_highlights()
  local highlight = vim.api.nvim_get_hl(0, { name = "RaccoonInlineDiffAddText", link = false })
  h.equal(highlight.fg, 0xABCDEF)
  h.equal(highlight.bg, 0x102030)
end)

h.test("host adapter copies real commit grid data without host mutation", function()
  local target = buffer({ "old value", "new value", "context" })
  local host_namespace = vim.api.nvim_create_namespace("raccoon_commits")
  vim.api.nvim_buf_set_extmark(target, host_namespace, 0, 0, {
    line_hl_group = "RaccoonDelete",
    sign_text = "-",
  })
  vim.api.nvim_buf_set_extmark(target, host_namespace, 1, 0, {
    line_hl_group = "RaccoonAdd",
    sign_text = "+",
  })
  local state = {
    active = true,
    grid_bufs = { target },
    select_generation = 3,
    current_page = 1,
    preview_generation = 0,
    focus_target = "sidebar",
  }
  package.loaded["raccoon.commits"] = { _get_state = function() return state end }
  package.loaded["raccoon.localcommits"] = nil
  package.loaded["raccoon.state"] = nil

  local before_lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
  local before_marks = marks(target, host_namespace)
  local snapshots = adapter.snapshots()
  h.equal(#snapshots, 1)
  h.equal(snapshots[1].route, "commit_grid")
  h.equal(snapshots[1].records[1].kind, "deletion")
  h.equal(snapshots[1].records[2].kind, "addition")
  h.equal(snapshots[1].records[3].kind, "context")
  h.deep_equal(vim.api.nvim_buf_get_lines(target, 0, -1, false), before_lines)
  h.deep_equal(marks(target, host_namespace), before_marks)
end)

h.test("host adapter identifies previews, maximized views, and Current changes", function()
  package.loaded["raccoon.commits"] = nil
  local grid = buffer({ "old", "new" })
  local maximum = buffer({ "old", "new" })
  local host_namespace = vim.api.nvim_create_namespace("raccoon_local_commits")
  for _, target in ipairs({ grid, maximum }) do
    vim.api.nvim_buf_set_extmark(target, host_namespace, 0, 0, { sign_text = "-", line_hl_group = "RaccoonDelete" })
    vim.api.nvim_buf_set_extmark(target, host_namespace, 1, 0, { sign_text = "+", line_hl_group = "RaccoonAdd" })
  end
  local state = {
    active = true,
    grid_bufs = { grid },
    maximize_buf = maximum,
    branch_commits = { { sha = nil, message = "Current changes" } },
    base_commits = {},
    selected_index = 1,
    focus_target = "filetree",
    filetree_preview_path = "sample.lua",
    select_generation = 2,
    current_page = 1,
    preview_generation = 4,
  }
  package.loaded["raccoon.localcommits"] = { _get_state = function() return state end }
  local snapshots = adapter.snapshots()
  h.equal(#snapshots, 2)
  h.equal(snapshots[1].route, "current_changes_preview")
  h.equal(snapshots[2].route, "current_changes_maximized")
end)

h.test("flat adapter copies patch data and lifecycle leaves deleted virtual lines host-owned", function()
  package.loaded["raccoon.commits"] = nil
  package.loaded["raccoon.localcommits"] = nil
  local target = buffer({ "new value" })
  vim.api.nvim_buf_set_name(target, "/tmp/raccoon-inline-host/sample.lua")
  local patch = "@@ -1,1 +1,1 @@\n-old value\n+new value\n"
  package.loaded["raccoon.state"] = {
    is_active = function() return true end,
    get_clone_path = function() return "/tmp/raccoon-inline-host" end,
    get_files = function() return { { filename = "sample.lua", patch = patch } } end,
  }
  local host_namespace = vim.api.nvim_create_namespace("raccoon_diff")
  vim.api.nvim_buf_set_extmark(target, host_namespace, 0, 0, {
    virt_lines = { { { "- old value", "RaccoonDelete" } } },
    virt_lines_above = true,
    sign_text = "-",
  })
  local host_marks_before = marks(target, host_namespace)
  local snapshots = adapter.snapshots()
  h.equal(#snapshots, 1)
  h.equal(snapshots[1].route, "flat_pr_additions")
  lifecycle._refresh(snapshots[1])
  wait_for_scheduled()
  h.equal(#marks(target, renderer.namespace()), 1)
  h.deep_equal(marks(target, host_namespace), host_marks_before)
  lifecycle.stop()
  h.equal(#marks(target, renderer.namespace()), 0)
  h.deep_equal(marks(target, host_namespace), host_marks_before)
end)

h.test("lifecycle cancels stale work after buffer changes", function()
  local target = buffer({ "old", "new" })
  local snapshot = {
    kind = "typed",
    route = "commit_grid",
    buffer = target,
    changedtick = vim.api.nvim_buf_get_changedtick(target),
    identity = "stale",
    records = {
      { kind = "deletion", content = "old", source_row = 0 },
      { kind = "addition", content = "new", source_row = 1 },
    },
  }
  lifecycle._refresh(snapshot)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, { "reused" })
  wait_for_scheduled()
  h.equal(#marks(target, renderer.namespace()), 0)
  lifecycle.stop()
end)

h.test("lifecycle generation keeps only the newest reused-buffer view", function()
  local target = buffer({ "abc", "axc" })
  local first = {
    kind = "typed",
    route = "commit_grid",
    buffer = target,
    changedtick = vim.api.nvim_buf_get_changedtick(target),
    identity = "first",
    records = {
      { kind = "deletion", content = "abc", source_row = 0 },
      { kind = "addition", content = "axc", source_row = 1 },
    },
  }
  lifecycle._refresh(first)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, { "abc", "abx" })
  local second = {
    kind = "typed",
    route = "commit_grid",
    buffer = target,
    changedtick = vim.api.nvim_buf_get_changedtick(target),
    identity = "second",
    records = {
      { kind = "deletion", content = "abc", source_row = 0 },
      { kind = "addition", content = "abx", source_row = 1 },
    },
  }
  lifecycle._refresh(second)
  vim.wait(500, function()
    return #marks(target, renderer.namespace()) == 2
  end, 10)
  local extension_marks = marks(target, renderer.namespace())
  h.equal(#extension_marks, 2)
  h.equal(extension_marks[1][3], 0)
  h.equal(extension_marks[1][4].end_col, 3)
  h.equal(extension_marks[2][3], 0)
  h.equal(extension_marks[2][4].end_col, 3)
  lifecycle.stop()
end)

h.test("buffer deletion during scheduled work is harmless", function()
  local target = buffer({ "old", "new" })
  lifecycle._refresh({
    kind = "typed",
    route = "commit_grid",
    buffer = target,
    changedtick = vim.api.nvim_buf_get_changedtick(target),
    identity = "deleted",
    records = {
      { kind = "deletion", content = "old", source_row = 0 },
      { kind = "addition", content = "new", source_row = 1 },
    },
  })
  vim.api.nvim_buf_delete(target, { force = true })
  wait_for_scheduled()
  lifecycle.stop()
end)

local failures_before_cleanup = 0
for _, target in ipairs(created_buffers) do
  if vim.api.nvim_buf_is_valid(target) then
    local ok = pcall(vim.api.nvim_buf_delete, target, { force = true })
    if not ok then failures_before_cleanup = failures_before_cleanup + 1 end
  end
end
h.equal(failures_before_cleanup, 0)

h.run()
