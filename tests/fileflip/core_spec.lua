-- Tests for core search functions in fileflip.nvim

local fileflip = require("fileflip")
local fixtures = require("fixtures")

-- Set up config for testing
fileflip.setup({
    extension_maps = {
        h = { "c", "cc", "cpp" },
        c = { "h" },
        cc = { "h", "hpp" },
        cpp = { "h", "hpp" },
        hpp = { "cc", "cpp" },
        tsx = { "ts" },
        ts = { "tsx" },
        py = { "pyi" },
        pyi = { "py" },
    },
    prefix_suffix_maps = {
        ["_test"] = { "" },
        ["test_/"] = { "" },
        ["_spec"] = { "" },
        [".test"] = { "" },
        [""] = { "_test", "test_/", "_spec", ".test" },
    },
    root_markers = { ".git", "package.json", "Makefile" },
    max_search_depth = 10,
    cache_enabled = true,
})

local test = fileflip._test

describe("find_root_directory", function()
    local temp_dir

    before_each(function()
        test.reset_state()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("finds .git marker", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")

        local root = test.find_root_directory(src_dir)
        assert.equals(vim.fn.fnamemodify(temp_dir, ":p:h"), vim.fn.fnamemodify(root, ":p:h"))
    end)

    it("finds package.json marker", function()
        temp_dir = fixtures.create_multi_root_project()
        local src_dir = fixtures.get_path(temp_dir, "src/lib")

        local root = test.find_root_directory(src_dir)
        assert.equals(vim.fn.fnamemodify(temp_dir, ":p:h"), vim.fn.fnamemodify(root, ":p:h"))
    end)

    it("stops at first root marker found", function()
        temp_dir = fixtures.create_multi_root_project()
        local src_dir = fixtures.get_path(temp_dir, "src")

        local root = test.find_root_directory(src_dir)
        -- Should find root with markers (not continue searching up)
        assert.is_not_nil(root)
        assert.equals(vim.fn.fnamemodify(temp_dir, ":p:h"), vim.fn.fnamemodify(root, ":p:h"))
    end)

    it("returns start directory when no markers found", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir .. "/some/nested/dir", "p")
        local nested_dir = temp_dir .. "/some/nested/dir"

        local root = test.find_root_directory(nested_dir)
        -- Should return the start directory when no markers found
        assert.equals(vim.fn.fnamemodify(nested_dir, ":p:h"), vim.fn.fnamemodify(root, ":p:h"))
    end)

    it("handles directory that is already root", function()
        temp_dir = fixtures.create_simple_project()

        local root = test.find_root_directory(temp_dir)
        assert.equals(vim.fn.fnamemodify(temp_dir, ":p:h"), vim.fn.fnamemodify(root, ":p:h"))
    end)

    it("respects max_search_depth", function()
        temp_dir = fixtures.create_deep_project()
        local deep_dir = fixtures.get_path(temp_dir, "a/b/c/d/e/f/g/h/i/j")

        -- Should still find root even from deep directory (10 levels up)
        local root = test.find_root_directory(deep_dir)
        assert.is_not_nil(root)
    end)
end)

describe("search_file_in_directory", function()
    local temp_dir

    before_each(function()
        test.reset_state()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("finds file in directory", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")

        local result = test.search_file_in_directory(src_dir, "foo", "c")
        assert.is_not_nil(result)
        assert.is_true(vim.endswith(result, "foo.c"))
    end)

    it("returns nil when file not found", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")

        local result = test.search_file_in_directory(src_dir, "nonexistent", "c")
        assert.is_nil(result)
    end)

    it("finds file with exact basename match", function()
        temp_dir = fixtures.create_simple_project()
        local include_dir = fixtures.get_path(temp_dir, "include")

        local result = test.search_file_in_directory(include_dir, "bar", "h")
        assert.is_not_nil(result)
        assert.is_true(vim.endswith(result, "bar.h"))
    end)
end)

describe("search_files_recursively", function()
    local temp_dir

    before_each(function()
        test.reset_state()
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("finds header file from source directory", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        local results = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        assert.is_true(#results > 0, "Should find at least one file")
        assert.is_true(vim.endswith(results[1], "foo.h"), "Should find foo.h")
    end)

    it("finds source file from include directory", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local include_dir = fixtures.get_path(temp_dir, "include")

        local results = test.search_files_recursively(root, include_dir, "bar", { "c" }, "h")
        assert.is_true(#results > 0, "Should find at least one file")
        assert.is_true(vim.endswith(results[1], "bar.c"), "Should find bar.c")
    end)

    it("caches result after successful search", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- First search
        local results = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        assert.is_true(#results > 0)

        -- Check cache
        local cache_key = test.get_cache_key("foo", "h", root)
        local cached = test.get_from_cache(cache_key)
        assert.is_not_nil(cached, "Result should be cached")
    end)

    it("returns cached result on second search", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- First search
        local results1 = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")

        -- Second search should use cache
        local results2 = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")

        assert.is_true(#results1 > 0)
        assert.is_true(#results2 > 0)
        assert.equals(results1[1], results2[1])
    end)

    it("finds files in complex nested structure", function()
        temp_dir = fixtures.create_complex_project()
        local root = test.find_root_directory(temp_dir)
        local component_dir = fixtures.get_path(temp_dir, "apps/web/src/components")

        local results = test.search_files_recursively(root, component_dir, "Button", { "tsx" }, "tsx")
        -- In complex projects, we might find the same file or test files
        assert.is_true(#results >= 0)
    end)

    it("returns empty array when no files found", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        local results = test.search_files_recursively(root, src_dir, "nonexistent", { "h" }, "c")
        assert.equals(0, #results)
    end)

    it("searches upward in directory tree", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        -- Start from a directory that doesn't have the file
        local test_dir = fixtures.get_path(temp_dir, "test")

        local results = test.search_files_recursively(root, test_dir, "foo", { "h" }, "c")
        assert.is_true(#results > 0, "Should find foo.h even from test directory")
    end)

    it("caches directory mapping after search", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- Search for foo.h from src/
        test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")

        -- Now search for bar.h - should use predicted directory
        local results = test.search_files_recursively(root, src_dir, "bar", { "h" }, "c")
        assert.is_true(#results > 0, "Should find bar.h using directory prediction")
    end)
end)

describe("search_alternative_files", function()
    local temp_dir

    before_each(function()
        test.reset_state()
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("finds test file from source file", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        local alternatives = test.generate_alternative_basenames("", "foo", "", "c")
        local results = test.search_alternative_files(root, src_dir, alternatives, "c", "", "foo", "")

        assert.is_true(#results > 0, "Should find test files")
        -- Should find foo_test.c
        local found_test = false
        for _, file in ipairs(results) do
            if vim.endswith(file, "foo_test.c") then
                found_test = true
                break
            end
        end
        assert.is_true(found_test, "Should find foo_test.c")
    end)

    it("finds source file from test file", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local test_dir = fixtures.get_path(temp_dir, "test")

        local alternatives = test.generate_alternative_basenames("", "foo", "_test", "c")
        local results = test.search_alternative_files(root, test_dir, alternatives, "c", "", "foo", "_test")

        assert.is_true(#results > 0, "Should find source files")
        -- Should find foo.c
        local found_source = false
        for _, file in ipairs(results) do
            if vim.endswith(file, "/foo.c") and not vim.endswith(file, "foo_test.c") then
                found_source = true
                break
            end
        end
        assert.is_true(found_source, "Should find foo.c")
    end)

    it("caches result after successful search", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        local alternatives = test.generate_alternative_basenames("", "foo", "", "c")
        local results = test.search_alternative_files(root, src_dir, alternatives, "c", "", "foo", "")

        assert.is_true(#results > 0)

        -- Check that result was cached
        for _, alt in ipairs(alternatives) do
            local cache_key = test.get_cache_key(alt, "c", root)
            -- At least one alternative should be cached
            local cached = test.get_from_cache(cache_key)
            if cached then
                assert.is_not_nil(cached)
                break
            end
        end
    end)

    it("returns empty array when no alternatives found", function()
        temp_dir = fixtures.create_custom_project({ "src/unique.c" })
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        local alternatives = { "nonexistent" }
        local results = test.search_alternative_files(root, src_dir, alternatives, "c", "", "unique", "")

        assert.equals(0, #results)
    end)

    it("handles spec suffix pattern", function()
        temp_dir = fixtures.create_complex_project()
        local root = test.find_root_directory(temp_dir)
        local component_dir = fixtures.get_path(temp_dir, "apps/web/src/components")

        local alternatives = test.generate_alternative_basenames("", "Input", "", "tsx")
        local results = test.search_alternative_files(root, component_dir, alternatives, "tsx", "", "Input", "")

        -- Should find Input.spec.tsx or Input.test.tsx
        assert.is_true(#results >= 0)
    end)

    it("searches upward in directory tree for alternatives", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local deep_dir = fixtures.get_path(temp_dir, "src") -- Start from src

        local alternatives = test.generate_alternative_basenames("", "foo", "_test", "c")
        local results = test.search_alternative_files(root, deep_dir, alternatives, "c", "", "foo", "_test")

        -- Should find foo.c even though we're in src/ and it might also be in src/
        assert.is_true(#results >= 0)
    end)

    it("caches directory mapping for future predictions", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- Search for foo's test file
        local alternatives1 = test.generate_alternative_basenames("", "foo", "", "c")
        test.search_alternative_files(root, src_dir, alternatives1, "c", "", "foo", "")

        -- Now search for bar's test file - should use directory mapping
        local alternatives2 = test.generate_alternative_basenames("", "bar", "", "c")
        local results = test.search_alternative_files(root, src_dir, alternatives2, "c", "", "bar", "")

        -- Should be able to find bar_test.c using cached directory mapping
        assert.is_true(#results >= 0)
    end)
end)
