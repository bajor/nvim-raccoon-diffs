local adapter = require("raccoon_inline_diff.host.raccoon")
local planner = require("raccoon_inline_diff.planner")
local renderer = require("raccoon_inline_diff.render")

local M = {}

local POLL_INTERVAL_MS = 100
local states = {}
local timer
local augroup
local running = false
local scan_queued = false
local diagnostics = "warn"
local diagnosed = {}

local function notify_once(message)
  if diagnostics == "silent" or diagnosed[message] then return end
  diagnosed[message] = true
  local level = diagnostics == "error" and vim.log.levels.ERROR or vim.log.levels.WARN
  vim.notify("raccoon-inline-diff: " .. message, level)
end

local function snapshot_is_current(snapshot, generation)
  local state = states[snapshot.buffer]
  return state ~= nil
    and state.generation == generation
    and vim.api.nvim_buf_is_valid(snapshot.buffer)
    and vim.api.nvim_buf_get_changedtick(snapshot.buffer) == snapshot.changedtick
end

local function append_ranges(marks, record, ranges, side, lines)
  if not record then return end
  local actual = lines[record.source_row + 1]
  if actual ~= record.content then return end
  for _, range in ipairs(ranges) do
    marks[#marks + 1] = {
      row = record.source_row,
      start_byte = range.start_byte,
      end_byte = range.end_byte,
      side = side,
    }
  end
end

local function plan_typed_snapshot(snapshot)
  local marks = {}
  local rows = planner.plan_typed_lines(snapshot.records)
  local lines = {}
  for _, record in ipairs(snapshot.records) do lines[record.source_row + 1] = record.content end
  for _, row in ipairs(rows) do
    if row.inline and not row.inline.suppressed then
      append_ranges(marks, row.deletion, row.inline.deletion_ranges, "deletion", lines)
      append_ranges(marks, row.addition, row.inline.addition_ranges, "addition", lines)
    end
  end
  return marks
end

local function plan_flat_snapshot(snapshot)
  local marks = {}
  local plan = planner.plan_patch(snapshot.patch)
  for _, row in ipairs(plan.rows) do
    if row.inline and row.addition and not row.inline.suppressed then
      local source_row = row.addition.new_line - 1
      local actual = snapshot.lines[source_row + 1]
      if actual == row.addition.content then
        for _, range in ipairs(row.inline.addition_ranges) do
          marks[#marks + 1] = {
            row = source_row,
            start_byte = range.start_byte,
            end_byte = range.end_byte,
            side = "addition",
          }
        end
      end
    end
  end
  return marks
end

local function compute(snapshot)
  if snapshot.kind == "typed" then return plan_typed_snapshot(snapshot) end
  if snapshot.kind == "flat" then return plan_flat_snapshot(snapshot) end
  error("unsupported host snapshot kind: " .. tostring(snapshot.kind))
end

function M._refresh(snapshot)
  local current = states[snapshot.buffer]
  if current and current.identity == snapshot.identity then return end
  local generation = (current and current.generation or 0) + 1
  states[snapshot.buffer] = { identity = snapshot.identity, generation = generation, route = snapshot.route }

  vim.schedule(function()
    if not snapshot_is_current(snapshot, generation) then return end
    local ok, marks = pcall(compute, snapshot)
    if not ok then
      renderer.clear(snapshot.buffer)
      notify_once("failed closed for " .. snapshot.route .. ": " .. tostring(marks))
      return
    end
    if not snapshot_is_current(snapshot, generation) then return end
    local applied, err = renderer.apply(snapshot.buffer, marks)
    if not applied and err then notify_once("failed closed for " .. snapshot.route .. ": " .. err) end
  end)
end

function M.scan()
  if not running then return end
  local ok, snapshots = pcall(adapter.snapshots)
  if not ok then
    notify_once("host adapter failed: " .. tostring(snapshots))
    return
  end
  local seen = {}
  for _, snapshot in ipairs(snapshots) do
    seen[snapshot.buffer] = true
    M._refresh(snapshot)
  end
  for buffer in pairs(states) do
    if not seen[buffer] then
      renderer.clear(buffer)
      states[buffer] = nil
    end
  end
end

local function queue_scan()
  if not running or scan_queued then return end
  scan_queued = true
  vim.schedule(function()
    scan_queued = false
    M.scan()
  end)
end

function M.start(options)
  M.stop()
  diagnostics = options.diagnostics
  local compatible, err = adapter.check_compatibility()
  if not compatible then
    notify_once(err)
    return false
  end
  running = true
  renderer.setup_highlights()
  augroup = vim.api.nvim_create_augroup("RaccoonInlineDiffLifecycle", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "TextChanged" }, {
    group = augroup,
    callback = queue_scan,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      renderer.setup_highlights()
      queue_scan()
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    callback = function(event) states[event.buf] = nil end,
  })

  timer = vim.uv.new_timer()
  if timer then timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(queue_scan)) end
  queue_scan()
  return true
end

function M.stop()
  running = false
  scan_queued = false
  if timer then
    pcall(timer.stop, timer)
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  for buffer in pairs(states) do renderer.clear(buffer) end
  states = {}
end

function M.is_running()
  return running
end

return M
