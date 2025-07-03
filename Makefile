# Shamelessly borrowed from https://github.com/ThePrimeagen/harpoon/blob/master/Makefile
fmt:
	echo "===> Formatting"
	stylua lua/ --config-path=.stylua.toml

lint:
	echo "===> Linting"
	luacheck lua/ --globals vim

pr-ready: fmt lint
