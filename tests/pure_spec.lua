local h = require("tests.helpers")
local planner = require("raccoon_inline_diff.planner")
local utf16 = require("raccoon_inline_diff.utf16")
local jsdiff = require("raccoon_inline_diff.vendor.jsdiff")
local fixtures = require("tests.fixtures.pierre_word_alt")

local function compact_ranges(ranges)
  local result = {}
  for _, range in ipairs(ranges) do
    result[#result + 1] = { range.start_utf16, range.end_utf16 }
  end
  return result
end

h.test("frozen Pierre word-alt fixtures", function()
  for index, fixture in ipairs(fixtures) do
    local result = planner.line_diff(fixture.deletion, fixture.addition)
    h.deep_equal(result.changes, fixture.changes, "change objects fixture " .. index)
    h.deep_equal(compact_ranges(result.deletion_ranges), fixture.deletion_ranges, "deletion ranges fixture " .. index)
    h.deep_equal(compact_ranges(result.addition_ranges), fixture.addition_ranges, "addition ranges fixture " .. index)
  end
end)

h.test("UTF-16 limit accepts 999 and 1000 but suppresses 1001", function()
  h.equal(planner.line_diff(string.rep("a", 999), string.rep("b", 999)).suppressed, false)
  h.equal(planner.line_diff(string.rep("a", 1000), string.rep("b", 1000)).suppressed, false)
  h.equal(planner.line_diff(string.rep("a", 1001), string.rep("b", 1001)).suppressed, true)
  h.equal(planner.line_diff(string.rep("😀", 500), string.rep("😁", 500)).suppressed, false)
  h.equal(planner.line_diff(string.rep("😀", 501), string.rep("😁", 501)).suppressed, true)
end)

h.test("UTF-16 coordinates convert only at valid UTF-8 boundaries", function()
  local value = "a😀é"
  h.equal(utf16.length(value), 4)
  h.equal(utf16.byte_column(value, 0), 0)
  h.equal(utf16.byte_column(value, 1), 1)
  h.equal(utf16.byte_column(value, 3), 5)
  h.equal(utf16.byte_column(value, 4), 7)
  h.raises(function() utf16.byte_column(value, 2) end, "not a code point boundary")
  h.raises(function() utf16.length("\255") end, "invalid UTF%-8")
end)

h.test("word tokenizer follows jsdiff Unicode and whitespace classes", function()
  local non_breaking_space = "\194\160"
  h.deep_equal(jsdiff.tokenize_words_with_space("é_1 漢\r\n😀" .. non_breaking_space .. "x"), {
    "é_1",
    " ",
    "漢",
    "\r\n",
    "😀",
    non_breaking_space,
    "x",
  })
end)

h.test("scheduled Myers chunks preserve exact output", function()
  local deletion = string.rep("a ", 120)
  local addition = string.rep("b\t", 120)
  local expected = planner.line_diff(deletion, addition)
  local yields = 0
  local actual = planner.line_diff(deletion, addition, function() yields = yields + 1 end)
  h.truthy(yields > 0, "test input must cross a Myers scheduling boundary")
  h.deep_equal(actual, expected)
end)

h.test("positional pairing covers equal and unequal block shapes", function()
  local records = {
    { kind = "deletion", content = "old-1", source_row = 0 },
    { kind = "deletion", content = "old-2", source_row = 1 },
    { kind = "addition", content = "new-1", source_row = 2 },
    { kind = "addition", content = "new-2", source_row = 3 },
    { kind = "addition", content = "new-3", source_row = 4 },
  }
  local rows = planner.plan_typed_lines(records)
  h.equal(#rows, 3)
  h.equal(rows[1].deletion.content, "old-1")
  h.equal(rows[1].addition.content, "new-1")
  h.equal(rows[2].deletion.content, "old-2")
  h.equal(rows[2].addition.content, "new-2")
  h.equal(rows[3].deletion, nil)
  h.equal(rows[3].addition.content, "new-3")

  local deletion_only = planner.plan_typed_lines({
    { kind = "deletion", content = "one" },
    { kind = "deletion", content = "two" },
  })
  h.equal(#deletion_only, 2)
  h.equal(deletion_only[1].addition, nil)
  h.equal(deletion_only[2].addition, nil)
end)

h.test("insertions and deletions never trigger similarity realignment", function()
  local function pairs(deletions, additions)
    local records = {}
    for _, content in ipairs(deletions) do
      records[#records + 1] = { kind = "deletion", content = content }
    end
    for _, content in ipairs(additions) do
      records[#records + 1] = { kind = "addition", content = content }
    end
    local result = {}
    for _, row in ipairs(planner.plan_typed_lines(records)) do
      result[#result + 1] = {
        row.deletion and row.deletion.content or false,
        row.addition and row.addition.content or false,
      }
    end
    return result
  end

  h.deep_equal(pairs({}, { "added" }), { { false, "added" } })
  h.deep_equal(pairs({ "deleted" }, {}), { { "deleted", false } })
  h.deep_equal(pairs({ "old-1", "old-2" }, { "new-1", "new-2" }), {
    { "old-1", "new-1" }, { "old-2", "new-2" },
  })
  h.deep_equal(pairs({ "old-1", "old-2", "old-3" }, { "new-1" }), {
    { "old-1", "new-1" }, { "old-2", false }, { "old-3", false },
  })

  h.deep_equal(pairs({ "old-1", "old-2" }, { "inserted", "new-1", "new-2" }), {
    { "old-1", "inserted" }, { "old-2", "new-1" }, { false, "new-2" },
  })
  h.deep_equal(pairs({ "old-1", "old-2" }, { "new-1", "inserted", "new-2" }), {
    { "old-1", "new-1" }, { "old-2", "inserted" }, { false, "new-2" },
  })
  h.deep_equal(pairs({ "old-1", "old-2" }, { "new-1", "new-2", "inserted" }), {
    { "old-1", "new-1" }, { "old-2", "new-2" }, { false, "inserted" },
  })

  h.deep_equal(pairs({ "deleted", "old-1", "old-2" }, { "new-1", "new-2" }), {
    { "deleted", "new-1" }, { "old-1", "new-2" }, { "old-2", false },
  })
  h.deep_equal(pairs({ "old-1", "deleted", "old-2" }, { "new-1", "new-2" }), {
    { "old-1", "new-1" }, { "deleted", "new-2" }, { "old-2", false },
  })
  h.deep_equal(pairs({ "old-1", "old-2", "deleted" }, { "new-1", "new-2" }), {
    { "old-1", "new-1" }, { "old-2", "new-2" }, { "deleted", false },
  })
end)

h.test("context and hunk boundaries prevent cross-block pairing", function()
  local patch = table.concat({
    "@@ -1,3 +1,3 @@\n",
    "-old-a\n",
    "+new-a\n",
    " context\n",
    "@@ -10,1 +10,2 @@\n",
    "-old-b\n",
    "+new-b\n",
    "+extra\n",
    "\\ No newline at end of file\n",
  })
  local plan = planner.plan_patch(patch)
  h.equal(#plan.hunks, 2)
  h.equal(#plan.rows, 4)
  h.equal(plan.rows[1].deletion.old_line, 1)
  h.equal(plan.rows[1].deletion.anchor_line, 0)
  h.equal(plan.rows[1].deletion.hunk_position, 1)
  h.equal(plan.rows[1].addition.new_line, 1)
  h.equal(plan.rows[1].addition.hunk_position, 2)
  h.equal(plan.rows[2].kind, "context")
  h.equal(plan.rows[3].deletion.old_line, 10)
  h.equal(plan.rows[3].deletion.anchor_line, 9)
  h.equal(plan.rows[3].addition.new_line, 10)
  h.equal(plan.rows[4].deletion, nil)
  h.equal(plan.rows[4].addition.no_eof_newline, true)
  h.equal(plan.rows[4].addition.content, "extra")
end)

h.test("planner output is deterministic", function()
  local first = planner.line_diff("repeat repeat !!!", "repeat !!! repeat")
  local second = planner.line_diff("repeat repeat !!!", "repeat !!! repeat")
  h.deep_equal(first, second)
end)
