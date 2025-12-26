# Uses https://github.com/casey/just
#     cargo install just
#     just fmt

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

test-file FILE:
	echo "===> Running test file: {{FILE}}"
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.busted').run('{{FILE}}')"

pr-ready: fmt lint test
