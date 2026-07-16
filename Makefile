.PHONY: test test-pure test-neovim test-host test-host-main test-host-stable lint

HOST_MAIN_COMMIT := ad11e402d2cc314653a8fd578d9923e8c9642448
HOST_STABLE_COMMIT := e71faeb393b2b03242bbd593e9900a3a16ecfcb1
PLENARY_COMMIT := b9fd5226c2f76c951fc8ed5923d85e4de065e509
HOST_MAIN_PATH ?= .deps/nvim-raccoon-main
HOST_STABLE_PATH ?= .deps/nvim-raccoon-v0.13.0
PLENARY_PATH ?= .deps/plenary.nvim
NVIM ?= nvim

test: test-pure test-neovim test-host lint

test-pure:
	lua tests/run.lua

test-neovim:
	$(NVIM) --headless -u tests/minimal_init.lua -l tests/neovim_spec.lua

$(HOST_MAIN_PATH)/.git:
	mkdir -p $(dir $(HOST_MAIN_PATH))
	git clone --no-checkout https://github.com/bajor/nvim-raccoon.git $(HOST_MAIN_PATH)
	git -C $(HOST_MAIN_PATH) checkout --detach $(HOST_MAIN_COMMIT)

$(HOST_STABLE_PATH)/.git:
	mkdir -p $(dir $(HOST_STABLE_PATH))
	git clone --no-checkout https://github.com/bajor/nvim-raccoon.git $(HOST_STABLE_PATH)
	git -C $(HOST_STABLE_PATH) checkout --detach $(HOST_STABLE_COMMIT)

$(PLENARY_PATH)/.git:
	mkdir -p $(dir $(PLENARY_PATH))
	git clone --no-checkout https://github.com/nvim-lua/plenary.nvim.git $(PLENARY_PATH)
	git -C $(PLENARY_PATH) checkout --detach $(PLENARY_COMMIT)

test-host: test-host-main test-host-stable

test-host-main: $(HOST_MAIN_PATH)/.git $(PLENARY_PATH)/.git
	$(NVIM) --headless --clean --cmd "set runtimepath^=$(HOST_MAIN_PATH)" \
		-c "lua assert(require('raccoon'))" -c qa
	$(NVIM) --headless --cmd "set runtimepath^=$(HOST_MAIN_PATH)" --cmd "set runtimepath^=$(PLENARY_PATH)" \
		-u tests/minimal_init.lua -l tests/host_compat_spec.lua

test-host-stable: $(HOST_STABLE_PATH)/.git $(PLENARY_PATH)/.git
	$(NVIM) --headless --clean --cmd "set runtimepath^=$(HOST_STABLE_PATH)" \
		-c "lua assert(require('raccoon'))" -c qa
	$(NVIM) --headless --cmd "set runtimepath^=$(HOST_STABLE_PATH)" --cmd "set runtimepath^=$(PLENARY_PATH)" \
		-u tests/minimal_init.lua -l tests/host_compat_spec.lua

lint:
	luacheck lua tests
	git diff --check
