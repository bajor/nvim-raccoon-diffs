.PHONY: test test-pure test-neovim lint

test: test-pure test-neovim lint

test-pure:
	lua tests/run.lua

test-neovim:
	nvim --headless -u tests/minimal_init.lua -l tests/neovim_spec.lua

lint:
	luacheck lua tests
	git diff --check
