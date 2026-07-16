# nvim-raccoon-diffs

Standalone inline-diff extension for
[nvim-raccoon](https://github.com/bajor/nvim-raccoon).

This repository is separate from `bajor/nvim-raccoon`. It adds strong changed
text backgrounds to Raccoon diff views without patching, replacing, or
modifying the host plugin.

The semantic planner reproduces the pinned Diffshub default from
`@pierre/diffs` 1.2.12: positional row pairing, `word-alt`,
`diffWordsWithSpace` from `diff@9.0.0`, and a 1000-UTF-16-unit per-line limit.
The differential development oracle reported zero mismatches across 10,000
paired lines and 2,000 randomized change blocks.

Semantic output is exact for the pinned behavior. Browser pixels are not
reproduced: Neovim renders native syntax highlighting and extmarks instead of
Shiki, HAST, CSS, and DOM elements.

## What this plugin does

Raccoon already highlights complete added and deleted lines. This extension
adds a stronger background only to the words or text fragments that changed
inside paired lines. It does not add a separate diff viewer or change how
Raccoon opens pull requests, commits, comments, or local changes.

The extension is automatic:

1. Install and configure `bajor/nvim-raccoon` normally.
2. Install this plugin after Raccoon.
3. Open any supported Raccoon diff view as usual.
4. The extension detects the view and adds inline highlights. No extension
   command or keymap is required.

## Is configuration required?

No extension configuration is required. The default setup is equivalent to:

```lua
require("raccoon_inline_diff").setup()
```

Raccoon itself must still be configured, including its GitHub credentials, as
described in the [Raccoon documentation](https://github.com/bajor/nvim-raccoon#configuration).
The extension reads supported Raccoon views but never reads or owns GitHub
credentials.

Optional extension settings are limited to enabling the plugin and controlling
compatibility diagnostics. They cannot change the pinned diff semantics.

## Requirements

- Neovim 0.10.4 or newer
- [`bajor/nvim-raccoon`](https://github.com/bajor/nvim-raccoon), installed and
  configured according to its documentation

The extension has no other direct runtime dependency. It does not require
Node.js, npm, Python, a native library, a browser, a network request, or an
external command. Raccoon's own transitive requirements remain unchanged.

## Installation

Install and configure Raccoon before this extension.

### lazy.nvim

```lua
return {
  {
    "bajor/nvim-raccoon",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("raccoon").setup()
    end,
  },
  {
    "bajor/nvim-raccoon-diffs",
    main = "raccoon_inline_diff",
    dependencies = { "bajor/nvim-raccoon" },
    opts = {},
  },
}
```

If Raccoon is already declared elsewhere in the lazy.nvim configuration, only
the second plugin specification is needed.

### vim-plug

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'bajor/nvim-raccoon'
Plug 'bajor/nvim-raccoon-diffs'

lua require('raccoon_inline_diff').setup()
```

Do not copy setup code into the host repository. Do not patch or fork the host
to install this extension.

## Setup

```lua
require("raccoon_inline_diff").setup({
  enabled = true,
  diagnostics = "warn",
})
```

Options:

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enabled` | boolean | `true` | Starts or stops attachment and clears extension marks when disabled. |
| `diagnostics` | `"silent"`, `"warn"`, or `"error"` | `"warn"` | Controls one-time incompatibility diagnostics. |

No option can change row pairing, tokenization, span merging, the algorithm,
the 1000-unit limit, Myers tie-breaking, or UTF-16 interpretation.

Disable the extension and restore plain host rendering:

```lua
require("raccoon_inline_diff").disable()
```

## Exact semantic behavior

### Positional row pairing

Within one contiguous change block, deletion row `i` pairs with addition row
`i`. Context and hunk boundaries end the block. The planner never performs
similarity matching, move detection, or `vim.diff` realignment.

For two deletions and three additions, rows are:

1. deletion 1 with addition 1
2. deletion 2 with addition 2
3. unpaired addition 3

Unpaired rows keep the host's whole-line background and receive no extension
inline decoration.

### Word-alt spans

For each paired row, the planner performs this pinned sequence:

1. Apply Pierre's `cleanLastNewline` behavior.
2. Measure JavaScript UTF-16 code units.
3. Suppress inline spans only when either side is longer than 1000 units.
4. Run `diffWordsWithSpace` from `diff@9.0.0`.
5. Apply Pierre's `word-alt` `pushOrJoinSpan` and final-item behavior.
6. Convert completed UTF-16 ranges to validated, zero-based, end-exclusive
   UTF-8 byte columns.

Exactly 1000 UTF-16 units are eligible. A 1001-unit line is suppressed. No
character refinement pass is added.

For example:

```diff
-old_timeout = calculate_timeout(config)
+new_timeout = calculate_timeout(options)
```

The deletion spans are `old_timeout` and `config`. The addition spans are
`new_timeout` and `options`. The identifiers are not refined to `old` and
`new`.

## Architecture and ownership

Data flows in one direction:

```text
Raccoon patch/state/extmarks
            |
            v
isolated read-only host adapter
            |
            v
immutable typed snapshot -> pure Pierre/jsdiff planner
            |                         |
            +-------------------------+
            v
extension-only extmark renderer
```

- `planner.lua`, `utf16.lua`, and `vendor/jsdiff.lua` form the pure semantic
  engine. They do not load Neovim or Raccoon.
- `host/raccoon.lua` copies the minimum required host data. It never mutates a
  returned host table.
- `render.lua` owns only the `raccoon_inline_diff` namespace.
- `lifecycle.lua` polls observable view generations, advances exact Myers work
  in scheduled coroutine chunks, rejects stale results, and clears extension
  state on detach.

The renderer uses `hl_mode = "combine"` and priority 200 so native syntax
foregrounds remain visible. Reapplication is idempotent.

Highlight groups:

- `RaccoonInlineDiffAddText`
- `RaccoonInlineDiffDeleteText`

When present, they default-link to `RaccoonAddText` and `RaccoonDeleteText`.
Current tested host versions do not define those groups, so the fallbacks are
`DiffAdd` and `DiffDelete`. Existing user definitions are never overwritten.

The extension never changes host buffer text, virtual lines, signs, keymaps,
window options, commands, comments, anchors, navigation, merge actions, sync
logic, or review coordinates. It never clears a host namespace.

## Host integration and compatibility

Raccoon currently exposes no documented inline-decoration API or lifecycle
events. The adapter therefore isolates these capability-checked private reads:

- `raccoon.state` getters for flat pull-request file patches
- `raccoon.commits._get_state()` for commit views
- `raccoon.localcommits._get_state()` for local views
- read-only inspection of the `raccoon_commits` and
  `raccoon_local_commits` real-line extmarks

The adapter does not call host rendering, refresh, Git, review, comment, or
navigation functions. It does not retain mutable host-owned tables in scheduled
work.

Private interfaces can change. On a missing loaded-route capability, the
extension fails closed, emits one diagnostic containing the missing capability,
and leaves the host untouched. The installed host commit is not exposed by
Raccoon, so runtime diagnostics report the version as unavailable; the exact
tested revisions are listed below.

### Compatibility matrix

| Host snapshot | Neovim | Real-row routes | Flat PR route | Deleted virtual lines | Test status |
| --- | --- | --- | --- | --- | --- |
| GitHub release `v0.13.0`, commit `e71faeb393b2b03242bbd593e9900a3a16ecfcb1` | 0.10.4 and 0.12.4 | commit grid, commit preview, maximized commit diff, local grid/preview/maximized, Current changes grid/preview/maximized and refresh | addition spans only | unsupported | automated |
| `main` snapshot `ad11e402d2cc314653a8fd578d9923e8c9642448` from 2026-07-16 | 0.10.4 and 0.12.4 | commit grid, commit preview, maximized commit diff, local grid/preview/maximized, Current changes grid/preview/maximized and refresh | addition spans only | unsupported | automated |

Every fully supported real-row route uses the same planner and renderer.
Working-directory refreshes are invalidated by host view generations, buffer
change ticks, and extension render generations.

Eligible expensive comparisons are never replaced by heuristics. The exact
Myers traversal yields between fixed-size iteration chunks so Neovim can cancel
stale work without changing traversal order or output.

### Flat pull-request limitation

Flat pull-request additions are real buffer rows, so they receive exact strong
addition spans. Deletions are host-owned `virt_lines`. The tested host versions
do not expose a supported hook that lets another plugin augment those chunks.

This extension therefore does not claim deleted virtual-line support. It does
not inspect, delete, recreate, truncate, or rewrite host virtual lines. A host
extension point would need to expose deletion text, stable row identity, and a
callback for extension-owned highlight chunks before both sides can be safely
rendered.

## Pinned upstream sources

### @pierre/diffs

- Repository: https://github.com/pierrecomputer/pierre
- Package: `@pierre/diffs@1.2.12`
- Tag: `diffs-v1.2.12`
- Commit: `9466c467ae6fc03501b6bca74c12f717d70293a7`
- License: Apache-2.0

### jsdiff

- Repository: https://github.com/kpdecker/jsdiff
- Package: `diff@9.0.0`
- Tag: `v9.0.0`
- Commit: `ed13aca03aa25735fafc0645d1185e7a1c68fd8c`
- License: BSD-3-Clause

Copied functions, source paths, mechanical Lua adaptations, complete licenses,
and fixture provenance are documented in
[`lua/raccoon_inline_diff/vendor/README.md`](lua/raccoon_inline_diff/vendor/README.md).

No updater or source-sync command is shipped. Future upstream changes require a
new explicit audit and fixture set.

## Verification

The normal suite requires no Node.js:

```sh
make test
```

It runs:

- pure Lua semantic tests and frozen oracle fixtures
- real Neovim extmark and lifecycle tests
- host-absent and host-enabled tests against both pinned host checkouts
- explicit route tests
- Lua lint
- `git diff --check`

The development-only oracle was outside this repository. It used deterministic
seed `0x5eed1234`, 10,000 paired lines, and 2,000 randomized change blocks. The
generated JSONL SHA-256 was
`3df0653e63a8f9146b2ed130c1e322d956d8f1e79d6e1a2ed2c4f6f676115db1`.
The final differential result was zero mismatches.

## Troubleshooting

1. Confirm Neovim is at least 0.10.4 with `:version`.
2. Confirm `:lua print(require("raccoon") ~= nil)` prints `true`.
3. Keep `diagnostics = "warn"` and reopen the Raccoon view.
4. Read the one-time missing-capability diagnostic, if emitted.
5. Run `:lua require("raccoon_inline_diff").refresh()` after changing plugin
   load order.
6. Disable the extension to confirm unchanged host behavior:
   `:lua require("raccoon_inline_diff").disable()`.

An incompatible route receives no extension marks. Raccoon continues rendering
its original whole-line diff unchanged.
