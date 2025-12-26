-- Minimal tests for core search functions in fileflip.nvim
-- These tests avoid file I/O and focus on testing logic

local fileflip = require("fileflip")

-- Set up minimal config for testing
fileflip.setup({
    extension_maps = {
        h = { "c" },
        c = { "h" },
    },
    cache_enabled = false,  -- Disable cache to avoid state issues
    ignore_filefliprc = true,  -- Don't try to load RC files
    autoload_filefliprc = false,
})

local test = fileflip._test

describe("find_root_directory (minimal)", function()
    it("returns directory when searching upward", function()
        -- Just test that the function doesn't crash
        local result = test.find_root_directory("/some/test/path")
        assert.is_not_nil(result)
        assert.is_string(result)
    end)
end)

describe("get_cache_key", function()
    it("generates cache key with components", function()
        local key = test.get_cache_key("foo", "c", "/project/root")
        assert.equals("/project/root:foo.c", key)
    end)
end)

describe("search_file_in_directory", function()
    it("returns nil for non-existent file", function()
        -- Test with a directory that definitely doesn't have the file
        local result = test.search_file_in_directory("/tmp", "nonexistent_unique_file_12345", "xyz")
        assert.is_nil(result)
    end)
end)
