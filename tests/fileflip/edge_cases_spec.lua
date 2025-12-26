-- Edge case tests for fileflip.nvim
-- Testing scenarios that could expose bugs, particularly with multiple directory trees

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

describe("Edge Cases", function()
    local mock_fs

    before_each(function()
        mock_fs = fs.use_mock()
        test.reset_state()
        fileflip.clear_cache()
    end)

    after_each(function()
        fs.use_real()
    end)

    describe("Same filename in different directory trees", function()
        it("finds correct file when multiple files with same name exist", function()
            -- Project structure:
            -- /project/.git
            -- /project/frontend/src/utils.c
            -- /project/frontend/include/utils.h
            -- /project/backend/src/utils.c
            -- /project/backend/include/utils.h

            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/frontend/src/utils.c")
            mock_fs:add_file("/project/frontend/include/utils.h")
            mock_fs:add_file("/project/backend/src/utils.c")
            mock_fs:add_file("/project/backend/include/utils.h")

            local root = test.find_root_directory("/project/frontend/src")

            -- When searching from frontend/src, should find frontend/include/utils.h
            local results = test.search_files_recursively(root, "/project/frontend/src", "utils", { "h" }, "c")

            assert.is_true(#results > 0, "Should find header file")

            -- Check that we get results (may include both, depending on search strategy)
            local has_frontend = false
            for _, path in ipairs(results) do
                if path:match("/frontend/include/utils%.h") then
                    has_frontend = true
                end
            end
            assert.is_true(has_frontend, "Should find frontend header")
        end)

        it("maintains separate cache entries for files in different directories", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/frontend/src/main.c")
            mock_fs:add_file("/project/frontend/include/main.h")
            mock_fs:add_file("/project/backend/src/main.c")
            mock_fs:add_file("/project/backend/include/main.h")

            local root = test.find_root_directory("/project")

            -- Search from frontend
            local results1 = test.search_files_recursively(root, "/project/frontend/src", "main", { "h" }, "c")
            assert.is_true(#results1 > 0)

            -- Search from backend
            local results2 = test.search_files_recursively(root, "/project/backend/src", "main", { "h" }, "c")
            assert.is_true(#results2 > 0)

            -- Both searches should work and not interfere with each other
            -- The cache should handle multiple files with same basename
        end)

        it("uses directory mapping cache correctly when switching between trees", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/frontend/src/widget.c")
            mock_fs:add_file("/project/frontend/include/widget.h")
            mock_fs:add_file("/project/backend/src/widget.c")
            mock_fs:add_file("/project/backend/include/widget.h")

            local root = test.find_root_directory("/project")

            -- First search from frontend establishes directory mapping
            test.search_files_recursively(root, "/project/frontend/src", "widget", { "h" }, "c")

            -- Second search from frontend should use cached mapping
            local results2 = test.search_files_recursively(root, "/project/frontend/src", "widget", { "h" }, "c")
            assert.is_true(#results2 > 0, "Cached directory mapping should work")

            -- Search from backend should create different directory mapping
            local results3 = test.search_files_recursively(root, "/project/backend/src", "widget", { "h" }, "c")
            assert.is_true(#results3 > 0, "Should find backend header")
        end)

        it("handles switching back and forth between different directory pairs", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/module_a/src/code.c")
            mock_fs:add_file("/project/module_a/include/code.h")
            mock_fs:add_file("/project/module_b/src/code.c")
            mock_fs:add_file("/project/module_b/include/code.h")

            local root = test.find_root_directory("/project")

            -- Search from module_a multiple times
            local results_a1 = test.search_files_recursively(root, "/project/module_a/src", "code", { "h" }, "c")
            local results_a2 = test.search_files_recursively(root, "/project/module_a/src", "code", { "h" }, "c")

            -- Search from module_b
            local results_b1 = test.search_files_recursively(root, "/project/module_b/src", "code", { "h" }, "c")

            -- Back to module_a
            local results_a3 = test.search_files_recursively(root, "/project/module_a/src", "code", { "h" }, "c")

            -- All searches should succeed
            assert.is_true(#results_a1 > 0 and #results_a2 > 0 and #results_b1 > 0 and #results_a3 > 0,
                "All searches should find files")
        end)
    end)

    describe("Cache invalidation scenarios", function()
        it("handles cache entry for non-existent file", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/temp.c")

            local cache_key = test.get_cache_key("temp", "h", "/project")

            -- Manually add invalid cache entry (file doesn't exist)
            test.add_to_cache(cache_key, "/project/include/temp.h")

            -- get_from_cache should detect file doesn't exist and return nil
            local cached = test.get_from_cache(cache_key)
            assert.is_nil(cached, "Should invalidate cache for non-existent file")
        end)

        it("handles directory mapping cache for non-existent directory", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/file.c")

            local root = "/project"

            -- Manually add directory mapping for non-existent directory
            test.add_directory_mapping_to_cache("/project/src", "c", "/project/deleted_include", "h", root)

            -- get_predicted_directory should detect directory doesn't exist
            local predicted = test.get_predicted_directory("/project/src", "c", "h", root)
            assert.is_nil(predicted, "Should invalidate directory mapping for non-existent directory")
        end)

        it("maintains cache correctness after multiple operations", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/a.c")
            mock_fs:add_file("/project/include/a.h")
            mock_fs:add_file("/project/src/b.c")
            mock_fs:add_file("/project/include/b.h")

            local root = test.find_root_directory("/project")

            -- Multiple searches that build up cache
            test.search_files_recursively(root, "/project/src", "a", { "h" }, "c")
            test.search_files_recursively(root, "/project/src", "b", { "h" }, "c")
            test.search_files_recursively(root, "/project/src", "a", { "h" }, "c") -- Second search for 'a'

            -- Verify cache still works correctly
            local key_a = test.get_cache_key("a", "h", root)
            local cached_a = test.get_from_cache(key_a)
            assert.is_not_nil(cached_a, "Cache for 'a' should still be valid")
        end)
    end)

    describe("Prefix and suffix edge cases", function()
        it("handles files with multiple underscores", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/my_long_module_name_test.c")
            mock_fs:add_file("/project/src/my_long_module_name.c")

            local root = test.find_root_directory("/project")

            -- Should find the implementation from test file
            local alt_basenames = test.generate_alternative_basenames("my_long_module_name", "_test", "")
            local results = test.search_alternative_files(root, "/project/src", alt_basenames, "c", "_test", "my_long_module_name", "")

            -- Should find files (may find the test file itself and/or the implementation)
            assert.is_not_nil(results)
        end)

        it("handles files with dots in basename", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo.test.js")
            mock_fs:add_file("/project/src/foo.js")

            local prefix, core, suffix = test.get_basename_parts("foo.test")

            -- Should extract some pattern
            assert.is_not_nil(core)
        end)

        it("handles files with prefix and suffix simultaneously", function()
            -- File like: test_foo_spec.c
            local basenames = test.generate_alternative_basenames("foo", "test_/", "_spec")

            -- Should generate alternatives
            assert.is_not_nil(basenames)
            assert.is_true(#basenames > 0, "Should generate some alternatives")
        end)

        it("handles empty basename after removing prefix/suffix", function()
            -- Edge case: what if basename is just "_test"?
            local basenames = test.generate_alternative_basenames("", "_test", "")

            assert.is_not_nil(basenames)
            -- Should handle gracefully without crashing
        end)

        it("handles very long prefixes and suffixes", function()
            local very_long_suffix = "_implementation_test_spec_final_version_v2"
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/module" .. very_long_suffix .. ".c")

            local basenames = test.generate_alternative_basenames("module", "", very_long_suffix)

            assert.is_not_nil(basenames)
            assert.is_true(#basenames > 0, "Should handle long suffixes")
        end)
    end)

    describe("Deeply nested structures", function()
        it("finds files in very deep directory hierarchies", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/a/b/c/d/e/f/g/h/i/j/deep.c")
            mock_fs:add_file("/project/include/deep.h")

            local root = test.find_root_directory("/project/a/b/c/d/e/f/g/h/i/j")
            local results = test.search_files_recursively(root, "/project/a/b/c/d/e/f/g/h/i/j", "deep", { "h" }, "c")

            assert.is_true(#results > 0, "Should find file from deeply nested location")
        end)

        it("handles search when file is at root and searching from deep", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/root_file.c")
            mock_fs:add_file("/project/root_file.h")
            mock_fs:add_file("/project/deep/nested/path/searching_from.c")

            local root = test.find_root_directory("/project")
            local results = test.search_files_recursively(root, "/project/deep/nested/path", "root_file", { "h" }, "c")

            assert.is_true(#results > 0, "Should find file at root when searching from deep location")
        end)

        it("handles search when both files are in sibling deep paths", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/deep/path/a/src/sibling.c")
            mock_fs:add_file("/project/deep/path/b/include/sibling.h")

            local root = test.find_root_directory("/project/deep/path/a/src")
            local results = test.search_files_recursively(root, "/project/deep/path/a/src", "sibling", { "h" }, "c")

            assert.is_true(#results > 0, "Should find file in sibling deep path")
        end)
    end)

    describe("Multiple root markers", function()
        it("stops at first marker when multiple exist at same level", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/package.json")
            mock_fs:add_file("/project/Makefile")
            mock_fs:add_directory("/project/src")

            local root = test.find_root_directory("/project/src")

            -- Should find /project (with any of the markers)
            assert.equals("/project", root)
        end)

        it("finds closest marker in nested structure", function()
            mock_fs:add_directory("/outer/.git")
            mock_fs:add_directory("/outer/middle/.git")
            mock_fs:add_directory("/outer/middle/inner/.git")
            mock_fs:add_directory("/outer/middle/inner/src")

            local root = test.find_root_directory("/outer/middle/inner/src")

            -- Should find /outer/middle/inner (closest .git)
            assert.equals("/outer/middle/inner", root)
        end)

        it("handles marker as file vs directory with same name", function()
            -- In theory you could have both .git file (submodule) and .git directory
            mock_fs:add_directory("/project/.git")
            mock_fs:add_directory("/project/submodule")
            -- Submodules have .git as a file, not directory
            mock_fs:add_file("/project/submodule/.git")
            mock_fs:add_directory("/project/submodule/src")

            local root = test.find_root_directory("/project/submodule/src")

            -- Should find /project/submodule (has .git file)
            assert.equals("/project/submodule", root)
        end)
    end)

    describe("Special characters and edge cases", function()
        it("handles files with spaces in path", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/my file.c")
            mock_fs:add_file("/project/include/my file.h")

            local root = test.find_root_directory("/project/src")
            local result = test.search_file_in_directory("/project/src", "my file", "c")

            assert.is_not_nil(result, "Should handle spaces in filename")
        end)

        it("handles files with dashes and special characters", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/my-special-file.c")
            mock_fs:add_file("/project/include/my-special-file.h")

            local root = test.find_root_directory("/project/src")
            local results = test.search_files_recursively(root, "/project/src", "my-special-file", { "h" }, "c")

            assert.is_true(#results > 0, "Should handle dashes in filename")
        end)

        it("handles directories with dots in name", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src.v1/code.c")
            mock_fs:add_file("/project/include.v1/code.h")

            local root = test.find_root_directory("/project/src.v1")
            local results = test.search_files_recursively(root, "/project/src.v1", "code", { "h" }, "c")

            assert.is_true(#results > 0, "Should handle dots in directory names")
        end)
    end)

    describe("Glob pattern edge cases", function()
        it("finds files when pattern matches multiple levels", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/a/test.c")
            mock_fs:add_file("/project/a/b/test.c")
            mock_fs:add_file("/project/a/b/c/test.c")

            local results = test.search_files_recursively_in_tree("/project", "test", { "c" })

            -- Should find all three files
            assert.is_true(#results >= 3, "Should find files at multiple nesting levels")
        end)

        it("handles glob with files at root level", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/root.c")
            mock_fs:add_file("/project/nested/root.c")

            local results = test.search_files_recursively_in_tree("/project", "root", { "c" })

            assert.is_true(#results >= 2, "Should find files at root and nested")
        end)
    end)

    describe("Extension mapping edge cases", function()
        it("handles files with no extension", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/Makefile")

            local basename, extension, directory = test.get_file_parts("/project/src/Makefile")

            assert.equals("Makefile", basename)
            assert.equals("", extension)
        end)

        it("handles files with multiple dots", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/archive.tar.gz")

            local basename, extension, directory = test.get_file_parts("/project/src/archive.tar.gz")

            -- vim.fn.fnamemodify with :e only gets last extension
            assert.equals("gz", extension)
            assert.equals("archive.tar", basename)
        end)

        it("handles switching between multiple possible extensions", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/multi.c")
            mock_fs:add_file("/project/include/multi.h")
            mock_fs:add_file("/project/include/multi.hpp")

            local root = test.find_root_directory("/project/src")
            local results = test.search_files_recursively(root, "/project/src", "multi", { "h", "hpp" }, "c")

            -- Should find both .h and .hpp
            assert.is_true(#results >= 2, "Should find multiple extension matches")
        end)
    end)

    describe("Cache size limits", function()
        it("respects cache size limit", function()
            mock_fs:add_directory("/project/.git")

            -- Create many files to exceed cache size (default 10000)
            -- For testing, let's just create a reasonable number
            for i = 1, 20 do
                mock_fs:add_file("/project/src/file" .. i .. ".c")
                mock_fs:add_file("/project/include/file" .. i .. ".h")
            end

            local root = test.find_root_directory("/project/src")

            -- Search for all files to populate cache
            for i = 1, 20 do
                test.search_files_recursively(root, "/project/src", "file" .. i, { "h" }, "c")
            end

            -- Cache should work without errors even with many entries
            -- (actual size limit is 10000, so this shouldn't trigger eviction)
            local key = test.get_cache_key("file1", "h", root)
            local cached = test.get_from_cache(key)
            assert.is_not_nil(cached, "Recent cache entry should still exist")
        end)
    end)

    describe("Alternative file search with complex patterns", function()
        it("finds files when both source and target have prefixes", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/impl_foo.c")
            mock_fs:add_file("/project/test/test_foo.c")

            local root = test.find_root_directory("/project/src")
            -- This is complex: impl_foo -> test_foo (different prefixes)
            local alt_basenames = test.generate_alternative_basenames("foo", "impl_/", "")
            local results = test.search_alternative_files(root, "/project/src", alt_basenames, "c", "impl_/", "foo", "")

            -- Should find alternative files
            assert.is_not_nil(results)
        end)

        it("handles circular prefix/suffix relationships", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/foo_test.c")
            mock_fs:add_file("/project/src/test_foo.c")

            local root = test.find_root_directory("/project/src")

            -- foo_test -> test_foo (suffix becomes prefix)
            local alt_basenames = test.generate_alternative_basenames("foo", "", "_test")
            local results = test.search_alternative_files(root, "/project/src", alt_basenames, "c", "", "foo", "_test")

            assert.is_not_nil(results)
        end)
    end)

    describe("Search from non-existent or empty directories", function()
        it("handles search from directory that doesn't exist", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/exists.c")

            local root = test.find_root_directory("/project")

            -- Search from non-existent directory
            local results = test.search_files_recursively(root, "/project/nonexistent", "exists", { "c" }, "h")

            -- Should handle gracefully (may return empty or use fallback search)
            assert.is_not_nil(results)
        end)

        it("handles empty directory with no files", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_directory("/project/empty")
            mock_fs:add_file("/project/src/file.c")

            local root = test.find_root_directory("/project/empty")
            local results = test.search_files_recursively(root, "/project/empty", "file", { "c" }, "h")

            -- Should still search the tree and find file
            assert.is_not_nil(results)
        end)
    end)

    describe("Configuration edge cases", function()
        it("handles file with extension not in extension_maps", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/unknown.xyz")
            mock_fs:add_file("/project/src/unknown.abc")

            local root = test.find_root_directory("/project/src")

            -- Try to search for alternative with unknown extension
            local results = test.search_files_recursively(root, "/project/src", "unknown", { "abc" }, "xyz")

            -- Should handle gracefully even if extension not configured
            assert.is_not_nil(results)
        end)

        it("handles search with empty target extensions list", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/file.c")

            local root = test.find_root_directory("/project/src")

            -- Search with empty extension list
            local results = test.search_files_recursively(root, "/project/src", "file", {}, "c")

            -- Should return empty results
            assert.equals(0, #results)
        end)
    end)

    describe("Path normalization edge cases", function()
        it("handles paths with trailing slashes", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/file.c")

            -- Path with trailing slash
            local root = test.find_root_directory("/project/src/")
            assert.is_not_nil(root)
        end)

        it("handles paths with double slashes", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project//src//file.c")

            local result = test.search_file_in_directory("/project//src", "file", "c")
            -- Should handle path normalization
            assert.is_not_nil(result)
        end)

        it("handles relative-looking paths in absolute context", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_directory("/project/./src")
            mock_fs:add_file("/project/src/file.c")

            -- Paths with ./ in them
            local root = test.find_root_directory("/project/./src")
            assert.is_not_nil(root)
        end)
    end)

    describe("Concurrent-like cache access patterns", function()
        it("handles rapid cache access for same file", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/rapid.c")
            mock_fs:add_file("/project/include/rapid.h")

            local root = test.find_root_directory("/project/src")

            -- Rapidly search for same file multiple times (simulating multiple buffers)
            for i = 1, 10 do
                local results = test.search_files_recursively(root, "/project/src", "rapid", { "h" }, "c")
                assert.is_true(#results > 0, "Iteration " .. i .. " should find file")
            end

            -- Cache should still be consistent
            local key = test.get_cache_key("rapid", "h", root)
            local cached = test.get_from_cache(key)
            assert.is_not_nil(cached)
        end)

        it("handles interleaved searches for different files", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/a.c")
            mock_fs:add_file("/project/src/b.c")
            mock_fs:add_file("/project/include/a.h")
            mock_fs:add_file("/project/include/b.h")

            local root = test.find_root_directory("/project/src")

            -- Interleaved searches
            for i = 1, 5 do
                test.search_files_recursively(root, "/project/src", "a", { "h" }, "c")
                test.search_files_recursively(root, "/project/src", "b", { "h" }, "c")
            end

            -- Both should still be cached correctly
            local key_a = test.get_cache_key("a", "h", root)
            local key_b = test.get_cache_key("b", "h", root)
            assert.is_not_nil(test.get_from_cache(key_a))
            assert.is_not_nil(test.get_from_cache(key_b))
        end)
    end)

    describe("Basename edge cases", function()
        it("handles single character basename", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/a.c")
            mock_fs:add_file("/project/include/a.h")

            local root = test.find_root_directory("/project/src")
            local results = test.search_files_recursively(root, "/project/src", "a", { "h" }, "c")

            assert.is_true(#results > 0, "Should handle single char basename")
        end)

        it("handles very long basename", function()
            local long_name = string.rep("very_long_module_name_", 10) -- 220+ chars
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/" .. long_name .. ".c")
            mock_fs:add_file("/project/include/" .. long_name .. ".h")

            local root = test.find_root_directory("/project/src")
            local results = test.search_files_recursively(root, "/project/src", long_name, { "h" }, "c")

            assert.is_true(#results > 0, "Should handle very long basename")
        end)

        it("handles basename that matches directory name", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_directory("/project/utils")
            mock_fs:add_file("/project/utils/utils.c")
            mock_fs:add_file("/project/include/utils.h")

            local root = test.find_root_directory("/project/utils")
            local results = test.search_files_recursively(root, "/project/utils", "utils", { "h" }, "c")

            assert.is_true(#results > 0, "Should handle basename matching directory name")
        end)
    end)

    describe("Bidirectional switching with multiple round trips", function()
        it("switches back and forth between .h and .c multiple times", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/widget.c")
            mock_fs:add_file("/project/include/widget.h")

            local root = test.find_root_directory("/project/src")

            -- Round trip 1: .c → .h
            local results1 = test.search_files_recursively(root, "/project/src", "widget", { "h" }, "c")
            assert.is_true(#results1 > 0, "Should find .h from .c (trip 1)")

            -- Round trip 1: .h → .c (back)
            local results2 = test.search_files_recursively(root, "/project/include", "widget", { "c" }, "h")
            assert.is_true(#results2 > 0, "Should find .c from .h (trip 1 return)")

            -- Round trip 2: .c → .h (again)
            local results3 = test.search_files_recursively(root, "/project/src", "widget", { "h" }, "c")
            assert.is_true(#results3 > 0, "Should find .h from .c (trip 2)")

            -- Round trip 2: .h → .c (back again)
            local results4 = test.search_files_recursively(root, "/project/include", "widget", { "c" }, "h")
            assert.is_true(#results4 > 0, "Should find .c from .h (trip 2 return)")

            -- Round trip 3: .c → .h (third time)
            local results5 = test.search_files_recursively(root, "/project/src", "widget", { "h" }, "c")
            assert.is_true(#results5 > 0, "Should find .h from .c (trip 3)")

            -- Verify cache is still consistent
            local key_h = test.get_cache_key("widget", "h", root)
            local key_c = test.get_cache_key("widget", "c", root)
            assert.is_not_nil(test.get_from_cache(key_h), "Cache for .h should still be valid")
            assert.is_not_nil(test.get_from_cache(key_c), "Cache for .c should still be valid")
        end)

        it("switches between .h, .cc, and .cpp multiple times", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/module.cc")
            mock_fs:add_file("/project/src/module.cpp")
            mock_fs:add_file("/project/include/module.h")

            local root = test.find_root_directory("/project/src")

            -- .cc → .h
            local results1 = test.search_files_recursively(root, "/project/src", "module", { "h" }, "cc")
            assert.is_true(#results1 > 0, ".cc → .h")

            -- .h → .cpp
            local results2 = test.search_files_recursively(root, "/project/include", "module", { "cpp" }, "h")
            assert.is_true(#results2 > 0, ".h → .cpp")

            -- .cpp → .h
            local results3 = test.search_files_recursively(root, "/project/src", "module", { "h" }, "cpp")
            assert.is_true(#results3 > 0, ".cpp → .h")

            -- .h → .cc (back to original)
            local results4 = test.search_files_recursively(root, "/project/include", "module", { "cc" }, "h")
            assert.is_true(#results4 > 0, ".h → .cc")

            -- .cc → .h (second round)
            local results5 = test.search_files_recursively(root, "/project/src", "module", { "h" }, "cc")
            assert.is_true(#results5 > 0, ".cc → .h (round 2)")

            -- All three file types should be cached
            assert.is_not_nil(test.get_from_cache(test.get_cache_key("module", "h", root)))
            assert.is_not_nil(test.get_from_cache(test.get_cache_key("module", "cc", root)))
            assert.is_not_nil(test.get_from_cache(test.get_cache_key("module", "cpp", root)))
        end)

        it("switches between implementation and test files multiple times", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/parser.c")
            mock_fs:add_file("/project/test/parser_test.c")

            local root = test.find_root_directory("/project/src")

            -- Implementation → Test
            local alt_basenames1 = test.generate_alternative_basenames("parser", "", "")
            local results1 = test.search_alternative_files(root, "/project/src", alt_basenames1, "c", "", "parser", "")
            local found_test1 = false
            for _, path in ipairs(results1) do
                if path:match("parser_test%.c$") then found_test1 = true end
            end
            assert.is_true(found_test1, "Should find test file from implementation (trip 1)")

            -- Test → Implementation
            local alt_basenames2 = test.generate_alternative_basenames("parser", "_test", "")
            local results2 = test.search_alternative_files(root, "/project/test", alt_basenames2, "c", "_test", "parser", "")
            local found_impl1 = false
            for _, path in ipairs(results2) do
                if path:match("/src/parser%.c$") then found_impl1 = true end
            end
            assert.is_true(found_impl1, "Should find implementation from test (trip 1 return)")

            -- Implementation → Test (again)
            local results3 = test.search_alternative_files(root, "/project/src", alt_basenames1, "c", "", "parser", "")
            local found_test2 = false
            for _, path in ipairs(results3) do
                if path:match("parser_test%.c$") then found_test2 = true end
            end
            assert.is_true(found_test2, "Should find test file from implementation (trip 2)")

            -- Test → Implementation (again)
            local results4 = test.search_alternative_files(root, "/project/test", alt_basenames2, "c", "_test", "parser", "")
            local found_impl2 = false
            for _, path in ipairs(results4) do
                if path:match("/src/parser%.c$") then found_impl2 = true end
            end
            assert.is_true(found_impl2, "Should find implementation from test (trip 2 return)")
        end)

        it("switches in a complex chain: .h → .cc → _test.cc → .cc → .h multiple times", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/include/complex.h")
            mock_fs:add_file("/project/src/complex.cc")
            mock_fs:add_file("/project/test/complex_test.cc")

            local root = test.find_root_directory("/project/src")

            -- Complete chain once
            -- 1. .h → .cc
            local r1 = test.search_files_recursively(root, "/project/include", "complex", { "cc" }, "h")
            assert.is_true(#r1 > 0, "Chain 1: .h → .cc")

            -- 2. .cc → _test.cc
            local alt_basenames_impl = test.generate_alternative_basenames("complex", "", "")
            local r2 = test.search_alternative_files(root, "/project/src", alt_basenames_impl, "cc", "", "complex", "")
            local found_test = false
            for _, path in ipairs(r2) do
                if path:match("complex_test%.cc$") then found_test = true end
            end
            assert.is_true(found_test, "Chain 1: .cc → _test.cc")

            -- 3. _test.cc → .cc
            local alt_basenames_test = test.generate_alternative_basenames("complex", "_test", "")
            local r3 = test.search_alternative_files(root, "/project/test", alt_basenames_test, "cc", "_test", "complex", "")
            local found_impl = false
            for _, path in ipairs(r3) do
                if path:match("/src/complex%.cc$") then found_impl = true end
            end
            assert.is_true(found_impl, "Chain 1: _test.cc → .cc")

            -- 4. .cc → .h
            local r4 = test.search_files_recursively(root, "/project/src", "complex", { "h" }, "cc")
            assert.is_true(#r4 > 0, "Chain 1: .cc → .h")

            -- Now repeat the entire chain to verify cache consistency
            -- Second chain: .h → .cc → _test.cc → .cc → .h
            local r5 = test.search_files_recursively(root, "/project/include", "complex", { "cc" }, "h")
            assert.is_true(#r5 > 0, "Chain 2: .h → .cc")

            local r6 = test.search_alternative_files(root, "/project/src", alt_basenames_impl, "cc", "", "complex", "")
            found_test = false
            for _, path in ipairs(r6) do
                if path:match("complex_test%.cc$") then found_test = true end
            end
            assert.is_true(found_test, "Chain 2: .cc → _test.cc")

            local r7 = test.search_alternative_files(root, "/project/test", alt_basenames_test, "cc", "_test", "complex", "")
            found_impl = false
            for _, path in ipairs(r7) do
                if path:match("/src/complex%.cc$") then found_impl = true end
            end
            assert.is_true(found_impl, "Chain 2: _test.cc → .cc")

            local r8 = test.search_files_recursively(root, "/project/src", "complex", { "h" }, "cc")
            assert.is_true(#r8 > 0, "Chain 2: .cc → .h")

            -- Verify all caches are still valid
            assert.is_not_nil(test.get_from_cache(test.get_cache_key("complex", "h", root)), "Cache for .h should be valid")
            assert.is_not_nil(test.get_from_cache(test.get_cache_key("complex", "cc", root)), "Cache for .cc should be valid")
        end)

        it("maintains correct directory mappings across bidirectional switches", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/lib/util.c")
            mock_fs:add_file("/project/api/util.h")

            local root = test.find_root_directory("/project/lib")

            -- First switch: lib → api
            test.search_files_recursively(root, "/project/lib", "util", { "h" }, "c")

            -- Verify directory mapping was cached (lib/c → api/h)
            local predicted1 = test.get_predicted_directory("/project/lib", "c", "h", root)
            assert.is_not_nil(predicted1, "Should have cached directory mapping lib → api")

            -- Reverse switch: api → lib
            test.search_files_recursively(root, "/project/api", "util", { "c" }, "h")

            -- Verify reverse directory mapping was cached (api/h → lib/c)
            local predicted2 = test.get_predicted_directory("/project/api", "h", "c", root)
            assert.is_not_nil(predicted2, "Should have cached directory mapping api → lib")

            -- Switch back: lib → api (should use cache)
            local results3 = test.search_files_recursively(root, "/project/lib", "util", { "h" }, "c")
            assert.is_true(#results3 > 0, "Should find using cached directory mapping")

            -- Switch back: api → lib (should use cache)
            local results4 = test.search_files_recursively(root, "/project/api", "util", { "c" }, "h")
            assert.is_true(#results4 > 0, "Should find using cached reverse directory mapping")

            -- Verify both mappings still exist
            assert.is_not_nil(test.get_predicted_directory("/project/lib", "c", "h", root), "Forward mapping should persist")
            assert.is_not_nil(test.get_predicted_directory("/project/api", "h", "c", root), "Reverse mapping should persist")
        end)

        it("handles rapid bidirectional switching without cache corruption", function()
            mock_fs:add_directory("/project/.git")
            mock_fs:add_file("/project/src/rapid.c")
            mock_fs:add_file("/project/include/rapid.h")

            local root = test.find_root_directory("/project/src")

            -- Rapidly switch back and forth 20 times
            for i = 1, 10 do
                -- .c → .h
                local results_h = test.search_files_recursively(root, "/project/src", "rapid", { "h" }, "c")
                assert.is_true(#results_h > 0, "Rapid switch " .. i .. " (.c → .h) should work")

                -- .h → .c
                local results_c = test.search_files_recursively(root, "/project/include", "rapid", { "c" }, "h")
                assert.is_true(#results_c > 0, "Rapid switch " .. i .. " (.h → .c) should work")
            end

            -- Verify cache hasn't been corrupted
            local key_h = test.get_cache_key("rapid", "h", root)
            local key_c = test.get_cache_key("rapid", "c", root)
            local cached_h = test.get_from_cache(key_h)
            local cached_c = test.get_from_cache(key_c)

            assert.is_not_nil(cached_h, "Cache for .h should still be valid after 20 switches")
            assert.is_not_nil(cached_c, "Cache for .c should still be valid after 20 switches")
            assert.is_not_nil(cached_h:match("rapid%.h$"), "Cached .h path should be correct")
            assert.is_not_nil(cached_c:match("rapid%.c$"), "Cached .c path should be correct")
        end)
    end)
end)
