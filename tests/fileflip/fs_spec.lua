-- Tests for the file system abstraction layer

local fs = require('fileflip.fs')

describe("File system abstraction", function()
    describe("Real file system", function()
        before_each(function()
            fs.use_real()
        end)

        it("uses vim.fn for operations", function()
            -- Just verify it doesn't crash
            local result = fs.isdirectory("/tmp")
            assert.is_boolean(result)
        end)
    end)

    describe("Mock file system", function()
        local mock_fs

        before_each(function()
            mock_fs = fs.use_mock()
        end)

        after_each(function()
            fs.use_real()
        end)

        it("starts with empty file system", function()
            assert.is_false(fs.filereadable("/any/file.txt"))
            assert.is_false(fs.isdirectory("/any/dir"))
        end)

        it("add_file creates a readable file", function()
            mock_fs:add_file("/project/src/foo.c", "content")

            assert.is_true(fs.filereadable("/project/src/foo.c"))
            assert.is_false(fs.isdirectory("/project/src/foo.c"))
        end)

        it("add_file creates parent directories", function()
            mock_fs:add_file("/a/b/c/d/file.txt")

            assert.is_true(fs.isdirectory("/a"))
            assert.is_true(fs.isdirectory("/a/b"))
            assert.is_true(fs.isdirectory("/a/b/c"))
            assert.is_true(fs.isdirectory("/a/b/c/d"))
            assert.is_true(fs.filereadable("/a/b/c/d/file.txt"))
        end)

        it("add_directory creates a directory", function()
            mock_fs:add_directory("/project/src")

            assert.is_true(fs.isdirectory("/project/src"))
            assert.is_false(fs.filereadable("/project/src"))
        end)

        it("globpath finds matching files", function()
            mock_fs:add_file("/project/foo.h")
            mock_fs:add_file("/project/bar.h")
            mock_fs:add_file("/project/baz.c")

            local results = fs.globpath("/project", "*.h", false, true)

            assert.equals(2, #results)
            -- Results should contain both .h files
            local has_foo = false
            local has_bar = false
            for _, path in ipairs(results) do
                if path:match("foo%.h") then
                    has_foo = true
                end
                if path:match("bar%.h") then
                    has_bar = true
                end
            end
            assert.is_true(has_foo, "Should find foo.h")
            assert.is_true(has_bar, "Should find bar.h")
        end)

        it("globpath with recursive pattern", function()
            mock_fs:add_file("/project/src/foo.c")
            mock_fs:add_file("/project/lib/bar.c")

            local results = fs.globpath("/project", "**/*.c", false, true)

            assert.is_true(#results >= 2, "Should find files in subdirectories")
        end)

        it("reset clears the file system", function()
            mock_fs:add_file("/test/file.txt")
            assert.is_true(fs.filereadable("/test/file.txt"))

            mock_fs:reset()

            assert.is_false(fs.filereadable("/test/file.txt"))
        end)

        it("fnamemodify delegates to vim.fn", function()
            -- This should still work even in mock mode
            local result = fs.fnamemodify("/path/to/file.txt", ":t")
            assert.equals("file.txt", result)
        end)
    end)

    describe("Switching between implementations", function()
        it("can switch from real to mock and back", function()
            -- Start with real
            fs.use_real()
            assert.equals(fs.real, fs.current)

            -- Switch to mock
            local mock = fs.use_mock()
            assert.equals(fs.mock, fs.current)

            -- Switch back to real
            fs.use_real()
            assert.equals(fs.real, fs.current)
        end)
    end)
end)
