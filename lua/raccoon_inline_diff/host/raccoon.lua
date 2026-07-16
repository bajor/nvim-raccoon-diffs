local M = {}

local MINIMUM_NVIM = { 0, 10, 4 }

local function nvim_at_least(required)
  local current = vim.version()
  if current.major ~= required[1] then return current.major > required[1] end
  if current.minor ~= required[2] then return current.minor > required[2] end
  return current.patch >= required[3]
end

---@return boolean
---@return string?
function M.check_compatibility()
  if not nvim_at_least(MINIMUM_NVIM) then
    return false, "Neovim 0.10.4 or newer is required"
  end
  local required_apis = {
    "nvim_buf_get_extmarks",
    "nvim_buf_set_extmark",
    "nvim_get_namespaces",
  }
  for _, name in ipairs(required_apis) do
    if type(vim.api[name]) ~= "function" then
      return false, "missing Neovim capability vim.api." .. name
    end
  end
  local ok = pcall(require, "raccoon")
  if not ok then
    return false, "host plugin bajor/nvim-raccoon is unavailable"
  end
  return true
end

local function buffer_lines(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local copy = {}
  for index, line in ipairs(lines) do copy[index] = line end
  return copy
end

local function host_extmarks(buffer, namespace)
  local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buffer, namespace, 0, -1, {
    details = true,
    hl_name = true,
  })
  if not ok then
    ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buffer, namespace, 0, -1, { details = true })
  end
  return ok and marks or {}
end

local function typed_records(buffer, namespace)
  local lines = buffer_lines(buffer)
  local kinds = {}
  for _, mark in ipairs(host_extmarks(buffer, namespace)) do
    local row = mark[2]
    local details = mark[4] or {}
    if details.sign_text == "+" or details.line_hl_group == "RaccoonAdd" then
      kinds[row] = "addition"
    elseif details.sign_text == "-" or details.line_hl_group == "RaccoonDelete" then
      kinds[row] = "deletion"
    end
  end

  local records = {}
  for index, content in ipairs(lines) do
    records[index] = {
      kind = kinds[index - 1] or "context",
      content = content,
      source_row = index - 1,
    }
  end
  return records
end

local function scalar(value)
  local kind = type(value)
  if kind == "string" or kind == "number" or kind == "boolean" then return tostring(value) end
  return "nil"
end

local function real_snapshot(buffer, namespace, route, state)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_buf_is_loaded(buffer) then return nil end
  local changedtick = vim.api.nvim_buf_get_changedtick(buffer)
  local records = typed_records(buffer, namespace)
  local signature = {}
  for _, record in ipairs(records) do signature[#signature + 1] = record.kind:sub(1, 1) end
  local identity = table.concat({
    route,
    scalar(state.select_generation),
    scalar(state.current_page),
    scalar(state.preview_generation),
    scalar(state.focus_target),
    scalar(state.filetree_preview_path),
    tostring(changedtick),
    table.concat(signature),
  }, ":")
  return {
    kind = "typed",
    route = route,
    buffer = buffer,
    changedtick = changedtick,
    identity = identity,
    records = records,
  }
end

local function selected_local_commit(state)
  local index = state.selected_index or 1
  local branch = state.branch_commits or {}
  if index <= #branch then return branch[index] end
  return (state.base_commits or {})[index - #branch]
end

local function collect_viewer(module_name, namespace_name, prefix, snapshots, seen, issues)
  local module = package.loaded[module_name]
  if module == nil then return end
  if type(module) ~= "table" or type(module._get_state) ~= "function" then
    issues[#issues + 1] = "host version unavailable; missing capability " .. module_name .. "._get_state"
    return
  end
  local ok, state = pcall(module._get_state)
  if not ok or type(state) ~= "table" or state.active ~= true then return end
  local namespace = vim.api.nvim_get_namespaces()[namespace_name]
  if not namespace then
    issues[#issues + 1] = "host version unavailable; missing namespace " .. namespace_name
    return
  end

  local current_changes = false
  if prefix == "local" then
    local commit = selected_local_commit(state)
    current_changes = type(commit) == "table" and commit.sha == nil
  end
  local route_prefix = current_changes and "current_changes" or prefix

  for index, buffer in ipairs(state.grid_bufs or {}) do
    if not seen[buffer] then
      local route = route_prefix .. "_grid"
      if index == 1 and state.focus_target == "filetree" and state.filetree_preview_path then
        route = route_prefix .. "_preview"
      end
      local snapshot = real_snapshot(buffer, namespace, route, state)
      if snapshot then
        snapshots[#snapshots + 1] = snapshot
        seen[buffer] = true
      end
    end
  end

  local maximize = state.maximize_buf
  if maximize and not seen[maximize] then
    local snapshot = real_snapshot(maximize, namespace, route_prefix .. "_maximized", state)
    if snapshot then
      snapshots[#snapshots + 1] = snapshot
      seen[maximize] = true
    end
  end
end

local function join_path(root, path)
  if vim.fs and vim.fs.joinpath then return vim.fs.joinpath(root, path) end
  return root:gsub("/$", "") .. "/" .. path
end

local function collect_flat(snapshots, seen, issues)
  local state = package.loaded["raccoon.state"]
  if state == nil then return end
  if type(state) ~= "table" or type(state.is_active) ~= "function"
    or type(state.get_clone_path) ~= "function"
    or type(state.get_files) ~= "function"
  then
    issues[#issues + 1] = "host version unavailable; missing flat-view state capabilities"
    return
  end
  local ok_active, active = pcall(state.is_active)
  if not ok_active or not active then return end
  local ok_root, root = pcall(state.get_clone_path)
  local ok_files, files = pcall(state.get_files)
  if not ok_root or type(root) ~= "string" or root == "" or not ok_files or type(files) ~= "table" then return end

  local buffers_by_name = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_is_loaded(buffer) then
      buffers_by_name[vim.api.nvim_buf_get_name(buffer)] = buffer
    end
  end
  for _, file in ipairs(files) do
    if type(file) == "table" and type(file.filename) == "string" and type(file.patch) == "string" then
      local buffer = buffers_by_name[join_path(root, file.filename)]
      if buffer and not seen[buffer] then
        local patch = file.patch
        local changedtick = vim.api.nvim_buf_get_changedtick(buffer)
        snapshots[#snapshots + 1] = {
          kind = "flat",
          route = "flat_pr_additions",
          buffer = buffer,
          changedtick = changedtick,
          identity = table.concat({ "flat", file.filename, tostring(changedtick), tostring(#patch), patch }, ":"),
          patch = patch,
          lines = buffer_lines(buffer),
        }
        seen[buffer] = true
      end
    end
  end
end

---Copy supported host views into immutable planner input snapshots.
---@return table[]
---@return string[]
function M.snapshots()
  local snapshots = {}
  local seen = {}
  local issues = {}
  collect_viewer("raccoon.commits", "raccoon_commits", "commit", snapshots, seen, issues)
  collect_viewer("raccoon.localcommits", "raccoon_local_commits", "local", snapshots, seen, issues)
  collect_flat(snapshots, seen, issues)
  return snapshots, issues
end

return M
