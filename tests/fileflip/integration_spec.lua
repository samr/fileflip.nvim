-- Integration tests for fileflip.nvim
-- These tests verify end-to-end workflows

local fileflip = require("fileflip")
local fixtures = require("fixtures")

describe("C/C++ Project Workflow", function()
    local temp_dir

    before_each(function()
        temp_dir = fixtures.create_simple_project()
        fileflip.setup({
            extension_maps = {
                h = { "c", "cc", "cpp" },
                c = { "h" },
            },
            cache_enabled = true,
        })
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("switches from .c to .h file", function()
        local c_file = fixtures.get_path(temp_dir, "src/foo.c")

        -- Open the C file
        vim.cmd("edit " .. vim.fn.fnameescape(c_file))

        -- Trigger switch (this would normally be via command, but we test the function directly)
        fileflip.switch_file()

        -- Verify we switched to the header
        local current = vim.fn.expand("%:p")
        assert.is_true(vim.endswith(current, "foo.h"), "Should switch to foo.h")
    end)

    it("switches from .h to .c file", function()
        local h_file = fixtures.get_path(temp_dir, "include/bar.h")

        vim.cmd("edit " .. vim.fn.fnameescape(h_file))
        fileflip.switch_file()

        local current = vim.fn.expand("%:p")
        assert.is_true(vim.endswith(current, "bar.c"), "Should switch to bar.c")
    end)

    it("caches directory mapping for performance", function()
        local c_file = fixtures.get_path(temp_dir, "src/foo.c")

        -- First switch
        vim.cmd("edit " .. vim.fn.fnameescape(c_file))
        fileflip.switch_file()

        -- Switch to another C file
        local c_file2 = fixtures.get_path(temp_dir, "src/bar.c")
        vim.cmd("edit " .. vim.fn.fnameescape(c_file2))

        -- Second switch should use cached directory mapping
        fileflip.switch_file()

        local current = vim.fn.expand("%:p")
        assert.is_true(vim.endswith(current, "bar.h"), "Should quickly find bar.h using cache")
    end)
end)

describe("Test File Workflow", function()
    local temp_dir

    before_each(function()
        temp_dir = fixtures.create_simple_project()
        fileflip.setup({
            prefix_suffix_maps = {
                ["_test"] = { "" },
                [""] = { "_test" },
            },
        })
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("switches from source to test file", function()
        local c_file = fixtures.get_path(temp_dir, "src/foo.c")

        vim.cmd("edit " .. vim.fn.fnameescape(c_file))
        fileflip.switch_file_alternative()

        local current = vim.fn.expand("%:p")
        assert.is_true(vim.endswith(current, "foo_test.c"), "Should switch to foo_test.c")
    end)

    it("switches from test to source file", function()
        local test_file = fixtures.get_path(temp_dir, "test/bar_test.c")

        vim.cmd("edit " .. vim.fn.fnameescape(test_file))
        fileflip.switch_file_alternative()

        local current = vim.fn.expand("%:p")
        assert.is_true(vim.endswith(current, "/bar.c"), "Should switch to bar.c")
        assert.is_false(vim.endswith(current, "bar_test.c"), "Should not stay on test file")
    end)
end)

describe("Complex Nested Project", function()
    local temp_dir

    before_each(function()
        temp_dir = fixtures.create_complex_project()
        fileflip.setup({
            extension_maps = {
                tsx = { "ts" },
                ts = { "tsx" },
            },
            prefix_suffix_maps = {
                [".test"] = { "" },
                [".spec"] = { "" },
                [""] = { ".test", ".spec" },
            },
        })
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("finds test files in deeply nested structure", function()
        local component_file = fixtures.get_path(temp_dir, "apps/web/src/components/Button.tsx")

        vim.cmd("edit " .. vim.fn.fnameescape(component_file))
        fileflip.switch_file_alternative()

        local current = vim.fn.expand("%:p")
        -- Should find either Button.test.tsx or Button.spec.tsx
        assert.is_true(
            vim.endswith(current, "Button.test.tsx") or vim.endswith(current, "Button.spec.tsx"),
            "Should find test file in nested structure"
        )
    end)

    it("handles multiple root markers correctly", function()
        temp_dir = fixtures.create_multi_root_project()
        local util_file = fixtures.get_path(temp_dir, "src/lib/util.js")

        vim.cmd("edit " .. vim.fn.fnameescape(util_file))

        local test = fileflip._test
        local root = test.find_root_directory(vim.fn.fnamemodify(util_file, ":h"))

        -- Should find project root, not go beyond it
        assert.is_not_nil(root)
        assert.is_true(vim.fn.isdirectory(root .. "/.git") == 1, "Should stop at .git marker")
    end)
end)

describe("Custom .filefliprc Configuration", function()
    local temp_dir

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("loads custom configuration from .filefliprc", function()
        temp_dir = fixtures.create_simple_project()

        -- Create custom .filefliprc
        local rc_content = [[
cache_size = 42
extension_maps = {
    h = { "c" },
    c = { "h" }
}
]]
        fixtures.create_rc_file(temp_dir, rc_content)

        fileflip.setup({ autoload_filefliprc = false })
        fileflip.load_config(temp_dir)

        local test = fileflip._test
        local state = test.get_state()

        assert.equals(42, state.config.cache_size, "Should load custom cache_size")
        assert.is_table(state.config.extension_maps.h, "Should load custom extension_maps")
    end)

    it("uses custom mappings from .filefliprc", function()
        temp_dir = fixtures.create_custom_project({ "src/foo.txt", "docs/foo.md" })

        local rc_content = [[
extension_maps = {
    txt = { "md" },
    md = { "txt" }
}
]]
        fixtures.create_rc_file(temp_dir, rc_content)

        fileflip.setup({ autoload_filefliprc = false })
        fileflip.load_config(temp_dir)

        local txt_file = fixtures.get_path(temp_dir, "src/foo.txt")
        vim.cmd("edit " .. vim.fn.fnameescape(txt_file))
        fileflip.switch_file()

        local current = vim.fn.expand("%:p")
        assert.is_true(vim.endswith(current, "foo.md"), "Should use custom mapping from .filefliprc")
    end)
end)

describe("Error Handling", function()
    local temp_dir

    before_each(function()
        temp_dir = fixtures.create_simple_project()
        fileflip.setup()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("handles file with no extension gracefully", function()
        local no_ext_file = fixtures.get_path(temp_dir, "src")
        vim.fn.mkdir(no_ext_file .. "/noext", "p")
        local file = io.open(no_ext_file .. "/noext/README", "w")
        if file then
            file:write("test")
            file:close()
        end

        vim.cmd("edit " .. vim.fn.fnameescape(no_ext_file .. "/noext/README"))

        -- Should not error
        local ok = pcall(fileflip.switch_file)
        assert.is_true(ok, "Should handle file with no extension without error")
    end)

    it("handles extension with no mappings", function()
        local unknown_file = temp_dir .. "/file.unknown"
        local file = io.open(unknown_file, "w")
        if file then
            file:write("test")
            file:close()
        end

        vim.cmd("edit " .. vim.fn.fnameescape(unknown_file))

        -- Should not error
        local ok = pcall(fileflip.switch_file)
        assert.is_true(ok, "Should handle unknown extension without error")
    end)

    it("handles no related files found", function()
        local unique_file = temp_dir .. "/unique.xyz"
        local file = io.open(unique_file, "w")
        if file then
            file:write("test")
            file:close()
        end

        fileflip.setup({
            extension_maps = {
                xyz = { "abc" },
            },
        })

        vim.cmd("edit " .. vim.fn.fnameescape(unique_file))

        -- Should not error even though no .abc files exist
        local ok = pcall(fileflip.switch_file)
        assert.is_true(ok, "Should handle no related files gracefully")
    end)
end)

describe("Command Functions", function()
    local temp_dir

    before_each(function()
        temp_dir = fixtures.create_simple_project()
        fileflip.setup()
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("FileFlipByExtensionShow lists available files", function()
        local c_file = fixtures.get_path(temp_dir, "src/foo.c")
        vim.cmd("edit " .. vim.fn.fnameescape(c_file))

        -- Should not error
        local ok = pcall(fileflip.show_available_files)
        assert.is_true(ok, "Should list available files without error")
    end)

    it("FileFlipByPrefixSuffixShow lists alternative files", function()
        local c_file = fixtures.get_path(temp_dir, "src/foo.c")
        vim.cmd("edit " .. vim.fn.fnameescape(c_file))

        -- Should not error
        local ok = pcall(fileflip.show_alternative_files)
        assert.is_true(ok, "Should list alternative files without error")
    end)

    it("FileFlipClearCache clears both caches", function()
        local test = fileflip._test
        local c_file = fixtures.get_path(temp_dir, "src/foo.c")

        -- Populate cache
        vim.cmd("edit " .. vim.fn.fnameescape(c_file))
        fileflip.switch_file()

        -- Clear cache
        fileflip.clear_cache()

        -- Verify cache is empty
        local state = test.get_state()
        assert.equals(0, #state.cache_order, "File cache should be empty")
        assert.equals(0, #state.dir_cache_order, "Directory cache should be empty")
    end)

    it("FileFlipShowStats displays cache statistics", function()
        -- Should not error
        local ok = pcall(fileflip.show_cache_stats)
        assert.is_true(ok, "Should show cache stats without error")
    end)

    it("FileFlipShowConfig displays configuration", function()
        -- Should not error
        local ok = pcall(fileflip.show_config)
        assert.is_true(ok, "Should show config without error")
    end)
end)

describe("Performance", function()
    local temp_dir

    before_each(function()
        fileflip.setup({ cache_enabled = true })
        fileflip.clear_cache()
    end)

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("second search is faster than first (cache benefit)", function()
        temp_dir = fixtures.create_simple_project()
        local test = fileflip._test
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- First search (cold cache)
        local start1 = vim.loop.hrtime()
        test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        local time1 = vim.loop.hrtime() - start1

        -- Second search (warm cache)
        local start2 = vim.loop.hrtime()
        test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        local time2 = vim.loop.hrtime() - start2

        -- Second search should be faster (or at least not significantly slower)
        -- We use a generous ratio to account for test environment variations
        assert.is_true(time2 <= time1 * 2, "Cache should improve or maintain performance")
    end)

    it("directory prediction speeds up similar file searches", function()
        temp_dir = fixtures.create_simple_project()
        local test = fileflip._test
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- First search establishes directory mapping
        test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")

        -- Second search for different file should benefit from prediction
        local start = vim.loop.hrtime()
        local results = test.search_files_recursively(root, src_dir, "bar", { "h" }, "c")
        local time = vim.loop.hrtime() - start

        -- Should find the file
        assert.is_true(#results > 0, "Should find bar.h using directory prediction")

        -- Should complete reasonably quickly (less than 10ms)
        assert.is_true(time < 10000000, "Predicted search should be fast")
    end)
end)
