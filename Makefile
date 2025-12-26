# Shamelessly borrowed from https://github.com/ThePrimeagen/harpoon/blob/master/Makefile
fmt:
	echo "===> Formatting"
	stylua lua/ --config-path=.stylua.toml

lint:
	echo "===> Linting"
	luacheck lua/ --globals vim

test:
	echo "===> Running tests"
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/fileflip/', { minimal_init = 'tests/minimal_init.lua' })"

test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file FILE=tests/fileflip/utils_spec.lua"; \
		exit 1; \
	fi
	echo "===> Running test file: $(FILE)"
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.busted').run('$(FILE)')"

pr-ready: fmt lint test

.PHONY: fmt lint test test-file pr-ready
