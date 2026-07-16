local M = { tests = {} }

local function inspect(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for key, child in pairs(value) do
    parts[#parts + 1] = tostring(key) .. "=" .. inspect(child)
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

local function deep_equal(left, right, seen)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  seen = seen or {}
  if seen[left] == right then return true end
  seen[left] = right
  for key, value in pairs(left) do
    if not deep_equal(value, right[key], seen) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

function M.test(name, callback)
  M.tests[#M.tests + 1] = { name = name, callback = callback }
end

function M.equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": actual=" .. inspect(actual) .. " expected=" .. inspect(expected), 2)
  end
end

function M.deep_equal(actual, expected, message)
  if not deep_equal(actual, expected) then
    error((message or "tables differ") .. ": actual=" .. inspect(actual) .. " expected=" .. inspect(expected), 2)
  end
end

function M.truthy(value, message)
  if not value then error(message or "expected truthy value", 2) end
end

function M.raises(callback, pattern)
  local ok, err = pcall(callback)
  if ok then error("expected callback to raise", 2) end
  if pattern and not tostring(err):match(pattern) then
    error("unexpected error: " .. tostring(err), 2)
  end
end

function M.run()
  local failures = 0
  for _, case in ipairs(M.tests) do
    local ok, err = xpcall(case.callback, debug.traceback)
    if ok then
      io.write("ok - " .. case.name .. "\n")
    else
      failures = failures + 1
      io.stderr:write("not ok - " .. case.name .. "\n" .. tostring(err) .. "\n")
    end
  end
  io.write(string.format("%d tests, %d failures\n", #M.tests, failures))
  if failures > 0 then os.exit(1) end
end

return M
