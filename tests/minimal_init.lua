-- Minimal init file for running tests
-- This sets up the bare minimum environment needed to test fileflip.nvim

-- Set test mode environment variable
vim.env.FILEFLIP_TEST_MODE = "1"

-- Add project root to runtimepath
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.runtimepath:append(root)

-- Add tests directory to Lua path for fixtures module
package.path = package.path .. ";" .. root .. "tests/?.lua"

-- Add plenary to runtimepath (assumes plenary is installed)
-- Common locations where plenary might be installed:
local plenary_locations = {
    -- Lazy.nvim
    vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
    -- Packer
    vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
    -- Manual install in opt
    vim.fn.stdpath("data") .. "/site/pack/*/opt/plenary.nvim",
}

local plenary_found = false
for _, path in ipairs(plenary_locations) do
    local expanded = vim.fn.glob(path)
    if expanded ~= "" and vim.fn.isdirectory(expanded) == 1 then
        vim.opt.runtimepath:append(expanded)
        plenary_found = true
        break
    end
end

if not plenary_found then
    error(
        "plenary.nvim not found! Please install it first:\n"
            .. "  Lazy: { 'nvim-lua/plenary.nvim' }\n"
            .. "  Packer: use 'nvim-lua/plenary.nvim'\n"
            .. "  Or clone to: "
            .. vim.fn.stdpath("data")
            .. "/site/pack/vendor/start/plenary.nvim"
    )
end

-- Set minimal vim options for testing
vim.opt.swapfile = false
vim.opt.hidden = true
vim.opt.compatible = false

-- Disable default plugins that might interfere
vim.g.loaded_gzip = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_netrwFileHandlers = 1

-- Verify plenary is loaded
local ok, _ = pcall(require, "plenary")
if not ok then
    error("Failed to load plenary.nvim even though it was found in runtimepath")
end

print("Test environment initialized successfully")
print("  - FILEFLIP_TEST_MODE: " .. vim.env.FILEFLIP_TEST_MODE)
print("  - plenary.nvim: loaded")
print("  - Project root: " .. root)
