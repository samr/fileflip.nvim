-- Test runner script for fileflip.nvim
-- This script runs all test files in the tests/fileflip directory

-- Prevent plenary from auto-exiting
vim.g.plenary_busted_no_auto_exit = true

-- Run each test file individually
local test_files = {
    'tests/fileflip/utils_spec.lua',
    'tests/fileflip/core_spec.lua',
    'tests/fileflip/cache_spec.lua',
    'tests/fileflip/config_spec.lua',
    'tests/fileflip/integration_spec.lua',
}

local total_success = 0
local total_failed = 0
local total_errors = 0
local all_passed = true

for i, file in ipairs(test_files) do
    print(string.format("\n========== Testing: %s (%d/%d) ==========", file, i, #test_files))

    local ok, err = pcall(function()
        require('plenary.busted').run(file)
    end)

    if not ok then
        print(string.format("[ERROR] Failed to run test file: %s", err))
        total_errors = total_errors + 1
        all_passed = false
    end
end

print(string.format("\n\n========== Test Summary =========="))
print(string.format("Test files run: %d", #test_files))
if total_errors > 0 then
    print(string.format("Errors: %d", total_errors))
end

-- Exit with proper code
if not all_passed or total_errors > 0 then
    vim.cmd('cquit!')  -- Exit with error code
else
    vim.cmd('quitall!')  -- Exit normally
end
