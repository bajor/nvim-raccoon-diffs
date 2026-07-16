-- Frozen from @pierre/diffs 1.2.12 and diff@9.0.0.
return {
  {
    deletion = "",
    addition = "",
    changes = {},
    deletion_ranges = {},
    addition_ranges = {},
  },
  {
    deletion = "a",
    addition = "b",
    changes = {
      { value = "a", count = 1, added = false, removed = true },
      { value = "b", count = 1, added = true, removed = false },
    },
    deletion_ranges = { { 0, 1 } },
    addition_ranges = { { 0, 1 } },
  },
  {
    deletion = "foo bar",
    addition = "foo baz",
    changes = {
      { value = "foo ", count = 2, added = false, removed = false },
      { value = "bar", count = 1, added = false, removed = true },
      { value = "baz", count = 1, added = true, removed = false },
    },
    deletion_ranges = { { 4, 7 } },
    addition_ranges = { { 4, 7 } },
  },
  {
    deletion = "foo  bar",
    addition = "foo\tbar",
    changes = {
      { value = "foo", count = 1, added = false, removed = false },
      { value = "  ", count = 1, added = false, removed = true },
      { value = "\t", count = 1, added = true, removed = false },
      { value = "bar", count = 1, added = false, removed = false },
    },
    deletion_ranges = { { 3, 5 } },
    addition_ranges = { { 3, 4 } },
  },
  {
    deletion = "old_timeout = calculate_timeout(config)",
    addition = "new_timeout = calculate_timeout(options)",
    changes = {
      { value = "old_timeout", count = 1, added = false, removed = true },
      { value = "new_timeout", count = 1, added = true, removed = false },
      { value = " = calculate_timeout(", count = 5, added = false, removed = false },
      { value = "config", count = 1, added = false, removed = true },
      { value = "options", count = 1, added = true, removed = false },
      { value = ")", count = 1, added = false, removed = false },
    },
    deletion_ranges = { { 0, 11 }, { 32, 38 } },
    addition_ranges = { { 0, 11 }, { 32, 39 } },
  },
  {
    deletion = "repeat repeat !!!",
    addition = "repeat !!! repeat",
    changes = {
      { value = "repeat ", count = 2, added = false, removed = false },
      { value = "repeat ", count = 2, added = false, removed = true },
      { value = "!!!", count = 3, added = false, removed = false },
      { value = " repeat", count = 2, added = true, removed = false },
    },
    deletion_ranges = { { 7, 14 } },
    addition_ranges = { { 10, 17 } },
  },
  {
    deletion = "e\204\129",
    addition = "é",
    changes = {
      { value = "e\204\129", count = 2, added = false, removed = true },
      { value = "é", count = 1, added = true, removed = false },
    },
    deletion_ranges = { { 0, 2 } },
    addition_ranges = { { 0, 1 } },
  },
  {
    deletion = "漢字",
    addition = "漢語",
    changes = {
      { value = "漢", count = 1, added = false, removed = false },
      { value = "字", count = 1, added = false, removed = true },
      { value = "語", count = 1, added = true, removed = false },
    },
    deletion_ranges = { { 1, 2 } },
    addition_ranges = { { 1, 2 } },
  },
  {
    deletion = "😀 x",
    addition = "😀 y",
    changes = {
      { value = "😀 ", count = 2, added = false, removed = false },
      { value = "x", count = 1, added = false, removed = true },
      { value = "y", count = 1, added = true, removed = false },
    },
    deletion_ranges = { { 3, 4 } },
    addition_ranges = { { 3, 4 } },
  },
  {
    deletion = "🧑🏽‍💻",
    addition = "🧑🏻‍💻",
    changes = {
      { value = "🧑", count = 1, added = false, removed = false },
      { value = "🏽", count = 1, added = false, removed = true },
      { value = "🏻", count = 1, added = true, removed = false },
      { value = "‍💻", count = 2, added = false, removed = false },
    },
    deletion_ranges = { { 2, 4 } },
    addition_ranges = { { 2, 4 } },
  },
  {
    deletion = "line\r\n",
    addition = "line changed\r\n",
    changes = {
      { value = "line", count = 1, added = false, removed = false },
      { value = " changed", count = 2, added = true, removed = false },
    },
    deletion_ranges = {},
    addition_ranges = { { 4, 12 } },
  },
}
