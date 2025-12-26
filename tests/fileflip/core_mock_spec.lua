-- Tests for core search functions using mock file system
-- This allows tests to run in headless mode without file I/O

local fileflip = require("fileflip")
local fs = require('fileflip.fs')

-- Set up config for testing
fileflip.setup({
    extension_maps = {
        h = { "c", "cc", "cpp" },
        c = { "h" },
        cc = { "h", "hpp" },
        cpp = { "h", "hpp" },
        hpp = { "cc", "cpp" },
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

describe("Core functions with mock file system", function()
    local mock_fs

    before_each(function()
        mock_fs = fs.use_mock()
        test.reset_state()
        fileflip.clear_cache()
    end)

    after_each(function()
        fs.use_real()
    end)

    describe("find_root_directory", function()
        it("finds .git marker", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_directory("/project/src")

            local root = test.find_root_directory("/project/src")
            assert.equals("/project", root)
        end)

        it("finds package.json marker", function()
            mock_fs:add_file("/project/package.json")
            mock_fs:add_directory("/project/src/lib")

            local root = test.find_root_directory("/project/src/lib")
            assert.equals("/project", root)
        end)

        it("finds Makefile marker", function()
            mock_fs:add_file("/project/Makefile")
            mock_fs:add_directory("/project/src")

            local root = test.find_root_directory("/project/src")
            assert.equals("/project", root)
        end)

        it("stops at first root marker found", function()
            -- Nested project with markers at multiple levels
            mock_fs:add_directory("/outer/.git")
            mock_fs:add_file("/outer/inner/package.json")
            mock_fs:add_directory("/outer/inner/src")

            local root = test.find_root_directory("/outer/inner/src")
            -- Should find inner package.json first (closest marker)
            assert.equals("/outer/inner", root)
        end)

        it("returns start directory when no markers found", function()
            mock_fs:add_directory("/project/some/nested/dir")

            local root = test.find_root_directory("/project/some/nested/dir")
            assert.equals("/project/some/nested/dir", root)
        end)

        it("handles directory that is already root", function()
            mock_fs:add_directory("/project/.git")

            local root = test.find_root_directory("/project")
            assert.equals("/project", root)
        end)

        it("respects max_search_depth", function()
            -- Create very deep directory without markers
            mock_fs:add_directory("/a/b/c/d/e/f/g/h/i/j/k/l/m")

            local root = test.find_root_directory("/a/b/c/d/e/f/g/h/i/j/k/l/m")
            -- Should return start dir when no markers found within depth limit
            assert.is_not_nil(root)
        end)
    end)

    describe("search_file_in_directory", function()
        it("finds file in directory", function()
            mock_fs:add_file("/project/src/foo.c")

            local result = test.search_file_in_directory("/project/src", "foo", "c")
            assert.equals("/project/src/foo.c", result)
        end)

        it("returns nil when file not found", function()
            mock_fs:add_directory("/project/src")

            local result = test.search_file_in_directory("/project/src", "nonexistent", "c")
            assert.is_nil(result)
        end)

        it("finds file with exact basename match", function()
            mock_fs:add_file("/project/include/bar.h")

            local result = test.search_file_in_directory("/project/include", "bar", "h")
            assert.equals("/project/include/bar.h", result)
        end)

        it("distinguishes between files with similar names", function()
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/src/foobar.c")

            local result = test.search_file_in_directory("/project/src", "foo", "c")
            assert.equals("/project/src/foo.c", result)
        end)
    end)

    describe("search_files_recursively", function()
        it("finds header file from source directory", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/include/foo.h")

            local root = test.find_root_directory("/project/src")
            local results = test.search_files_recursively(root, "/project/src", "foo", { "h" }, "c")

            assert.is_true(#results > 0, "Should find at least one file")
            local found_foo_h = false
            for _, path in ipairs(results) do
                if path:match("foo%.h$") then
                    found_foo_h = true
                    break
                end
            end
            assert.is_true(found_foo_h, "Should find foo.h")
        end)

        it("finds source file from include directory", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/bar.c")
            mock_fs:add_file("/project/include/bar.h")

            local root = test.find_root_directory("/project/include")
            local results = test.search_files_recursively(root, "/project/include", "bar", { "c" }, "h")

            assert.is_true(#results > 0, "Should find at least one file")
        end)

        it("searches upward in directory tree", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/deep/nested/code.c")
            mock_fs:add_file("/project/include/code.h")

            local root = test.find_root_directory("/project/src/deep/nested")
            local results = test.search_files_recursively(root, "/project/src/deep/nested", "code", { "h" }, "c")

            assert.is_true(#results > 0, "Should find file in parent directories")
        end)

        it("uses glob to find files recursively", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/lib/util/helper.c")
            mock_fs:add_file("/project/include/util/helper.h")

            local root = test.find_root_directory("/project/lib/util")
            local results = test.search_files_recursively(root, "/project/lib/util", "helper", { "h" }, "c")

            assert.is_true(#results > 0, "Should find file via recursive glob")
        end)
    end)

    describe("search_files_recursively_in_tree", function()
        it("finds files matching basename and extensions", function()
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/src/foo.cc")
            mock_fs:add_file("/project/include/foo.h")
            mock_fs:add_file("/project/include/foo.hpp")

            local results = test.search_files_recursively_in_tree("/project", "foo", { "h", "hpp" })

            -- Should find both .h and .hpp files
            assert.is_true(#results >= 2, "Should find multiple extensions")
        end)

        it("returns empty list when no files found", function()
            mock_fs:add_directory("/project/src")

            local results = test.search_files_recursively_in_tree("/project", "nonexistent", { "c" })

            assert.equals(0, #results)
        end)

        it("finds files in nested directories", function()
            mock_fs:add_file("/project/deep/nested/path/test.c")

            local results = test.search_files_recursively_in_tree("/project", "test", { "c" })

            assert.is_true(#results > 0, "Should find files in deep nesting")
        end)
    end)

    describe("search_alternative_files", function()
        it("finds test file from implementation", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/test/foo_test.c")

            local root = test.find_root_directory("/project/src")
            -- Generate alternative basenames for foo -> foo_test
            local alternative_basenames = test.generate_alternative_basenames("", "foo", "", "c")
            local results = test.search_alternative_files(root, "/project/src", alternative_basenames, "c", "", "foo", "")

            local found_test = false
            for _, path in ipairs(results) do
                if path:match("foo_test%.c$") then
                    found_test = true
                    break
                end
            end
            assert.is_true(found_test, "Should find foo_test.c")
        end)

        it("finds implementation from test file", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/bar.c")
            mock_fs:add_file("/project/test/bar_test.c")

            local root = test.find_root_directory("/project/test")
            -- Generate alternative basenames for bar_test -> bar
            local alternative_basenames = test.generate_alternative_basenames("", "bar", "_test", "c")
            local results = test.search_alternative_files(root, "/project/test", alternative_basenames, "c", "", "bar", "_test")

            local found_impl = false
            for _, path in ipairs(results) do
                if path:match("bar%.c$") and not path:match("_test") then
                    found_impl = true
                    break
                end
            end
            assert.is_true(found_impl, "Should find bar.c")
        end)

        it("finds spec file from implementation", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/module.c")
            mock_fs:add_file("/project/test/module_spec.c")

            local root = test.find_root_directory("/project/src")
            -- Generate alternative basenames for module -> module_spec
            local alternative_basenames = test.generate_alternative_basenames("", "module", "", "c")
            local results = test.search_alternative_files(root, "/project/src", alternative_basenames, "c", "", "module", "")

            local found_spec = false
            for _, path in ipairs(results) do
                if path:match("module_spec%.c$") then
                    found_spec = true
                    break
                end
            end
            assert.is_true(found_spec, "Should find module_spec.c")
        end)
    end)

    describe("Caching", function()
        it("caches file search results", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/include/foo.h")

            local root = test.find_root_directory("/project/src")

            -- First search
            local results1 = test.search_files_recursively(root, "/project/src", "foo", { "h" }, "c")
            assert.is_true(#results1 > 0)

            -- Check cache
            local cache_key = test.get_cache_key("foo", "h", root)
            local cached = test.get_from_cache(cache_key)
            assert.is_not_nil(cached, "Result should be cached")
        end)

        it("returns cached result on subsequent searches", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/include/foo.h")

            local root = test.find_root_directory("/project/src")

            -- First search populates cache
            test.search_files_recursively(root, "/project/src", "foo", { "h" }, "c")

            -- Second search should use cache (verify by checking cache before searching)
            local cache_key = test.get_cache_key("foo", "h", root)
            local cached_before = test.get_from_cache(cache_key)

            local results2 = test.search_files_recursively(root, "/project/src", "foo", { "h" }, "c")

            assert.is_not_nil(cached_before)
            assert.is_true(#results2 > 0)
        end)

        it("clears cache when requested", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/include/foo.h")

            local root = test.find_root_directory("/project/src")

            -- Populate cache
            test.search_files_recursively(root, "/project/src", "foo", { "h" }, "c")

            local cache_key = test.get_cache_key("foo", "h", root)
            assert.is_not_nil(test.get_from_cache(cache_key), "Cache should have entry")

            -- Clear cache
            fileflip.clear_cache()

            -- Cache should be empty
            assert.is_nil(test.get_from_cache(cache_key), "Cache should be cleared")
        end)
    end)
end)
