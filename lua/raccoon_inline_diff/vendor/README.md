# Vendored semantic sources

This directory contains a mechanical Lua adaptation required to reproduce the
pinned browser implementation without a runtime JavaScript dependency.

## jsdiff

- Project: jsdiff
- Repository: https://github.com/kpdecker/jsdiff
- Package: `diff@9.0.0`
- Tag: `v9.0.0`
- Commit: `ed13aca03aa25735fafc0645d1185e7a1c68fd8c`
- License: BSD-3-Clause; complete text in `licenses/jsdiff.txt`
- Source paths: `src/diff/base.ts` and the `WordsWithSpaceDiff` portion of
  `src/diff/word.ts`
- Local destination: `lua/raccoon_inline_diff/vendor/jsdiff.lua`
- Copied behavior: `diffWordsWithSpace`, word-with-space tokenization,
  synchronous Myers traversal, equality, tie-breaking, component construction,
  and token joining

Mechanical adaptations:

- TypeScript classes and overloads became one Lua module.
- JavaScript zero-based positions are retained as numeric values while Lua
  table access adds one at the access boundary.
- The pinned Unicode regular-expression ranges are explicit code-point tests.
- ECMAScript whitespace is an explicit code-point set.
- JavaScript `u`-mode fallback tokens use the local validating UTF-8 decoder so
  each token is one Unicode code point.
- Linked change components use Lua tables and retain the upstream branch order
  and deletion-preferred tie behavior.
- A scheduling hook may yield after every 4096 Myers diagonal steps. The hook
  runs only between iterations and retains the upstream traversal order and
  result.
- Upstream async callbacks, timeout, abort, comparator, and unrelated diff
  modes were omitted because the extension exposes only the default
  `diffWordsWithSpace` behavior.

## @pierre/diffs

- Project: Pierre diffs
- Repository: https://github.com/pierrecomputer/pierre
- Package: `@pierre/diffs@1.2.12`
- Tag: `diffs-v1.2.12`
- Commit: `9466c467ae6fc03501b6bca74c12f717d70293a7`
- License: Apache-2.0; complete text in `licenses/pierre-diffs.txt`
- Source paths: `packages/diffs/src/utils/cleanLastNewline.ts`,
  `packages/diffs/src/utils/parseDiffDecorations.ts`,
  `packages/diffs/src/utils/renderDiffWithHighlighter.ts`,
  `packages/diffs/src/utils/parsePatchFiles.ts`, and
  `packages/diffs/src/utils/iterateOverDiff.ts`
- Local destination: `lua/raccoon_inline_diff/planner.lua`
- Copied behavior: final-newline cleanup, `word-alt` span joining,
  `computeLineDiffDecorations`, context/change grouping, and ordinal split-row
  pairing

Mechanical adaptations:

- HAST decoration objects became UTF-16 ranges plus validated Neovim byte
  ranges.
- Browser line indexes became host-independent line records.
- Optional scheduling hooks yield between exact comparisons, typed rows, and
  patch parsing chunks without changing semantic output.
- The parser accepts the per-file unified patches exposed by nvim-raccoon and
  retains old lines, new lines, post-image anchors, hunk positions, hunk
  boundaries, and original source rows.
- Syntax highlighting, DOM, React, Shiki, worker, cache, and browser-rendering
  code were not copied.

## Fixture provenance

Vendoring date: 2026-07-16.

The development oracle ran from `/tmp` against the installed pinned packages.
It used seed `0x5eed1234`, 10,000 paired-line cases, and 2,000 randomized change
blocks. The complete generated JSONL SHA-256 was
`3df0653e63a8f9146b2ed130c1e322d956d8f1e79d6e1a2ed2c4f6f676115db1`.
The differential comparison reported zero mismatches. Representative outputs
are frozen in `tests/fixtures/pierre_word_alt.lua`; committed tests require no
Node.js.

Vendoring is required because runtime Node.js and extra Neovim plugin
dependencies are intentionally prohibited.
