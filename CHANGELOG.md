# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.1] - 2026-09-25

### Fixed

- Stop copying every tracked buffer's text on each 100 ms poll. Snapshots now
  carry a cheap identity and copy buffer lines only when the view changed; a
  large flat pull request with ten 20,000-line files went from about 32 ms of
  main-thread work per poll to effectively zero while idle.

## [0.1.0] - 2026-07-16

### Added

- Add the standalone `raccoon_inline_diff` setup API and lifecycle.
- Add exact pinned Pierre `word-alt` and jsdiff 9.0.0 semantics in pure Lua.
- Add extension-owned Neovim rendering for supported real-row Raccoon views and
  flat pull-request addition rows.
- Run exact Myers comparisons in cancellable scheduled coroutine chunks.
- Add frozen oracle fixtures, pinned host compatibility tests, CI, complete
  upstream licenses, and vendoring documentation.
- Document that deleted flat-view virtual lines remain unsupported until the
  host exposes a safe external decoration hook.
