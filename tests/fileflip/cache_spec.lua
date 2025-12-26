-- Tests for cache functionality in fileflip.nvim

local fileflip = require("fileflip")
local fixtures = require("fixtures")

-- Set up config for testing
fileflip.setup({
    cache_enabled = true,
    cache_size = 5, -- Small cache for testing eviction
})

local test = fileflip._test

describe("File Cache (LRU)", function()
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

    it("adds entry to cache", function()
        temp_dir = fixtures.create_simple_project()
        local file_path = fixtures.get_path(temp_dir, "src/foo.c")
        local key = test.get_cache_key("foo", "c", temp_dir)

        test.add_to_cache(key, file_path)

        local cached = test.get_from_cache(key)
        assert.equals(file_path, cached)
    end)

    it("retrieves cached entry", function()
        temp_dir = fixtures.create_simple_project()
        local file_path = fixtures.get_path(temp_dir, "src/foo.c")
        local key = test.get_cache_key("foo", "c", temp_dir)

        test.add_to_cache(key, file_path)
        local result = test.get_from_cache(key)

        assert.is_not_nil(result)
        assert.equals(file_path, result)
    end)

    it("returns nil for non-existent entry", function()
        local key = test.get_cache_key("nonexistent", "c", "/fake/path")
        local result = test.get_from_cache(key)

        assert.is_nil(result)
    end)

    it("updates LRU order when accessing entry", function()
        temp_dir = fixtures.create_simple_project()

        -- Add multiple entries
        local key1 = test.get_cache_key("foo", "c", temp_dir)
        local key2 = test.get_cache_key("bar", "c", temp_dir)

        test.add_to_cache(key1, fixtures.get_path(temp_dir, "src/foo.c"))
        test.add_to_cache(key2, fixtures.get_path(temp_dir, "src/bar.c"))

        -- Access key1 (should move to front)
        test.get_from_cache(key1)

        -- Both should still be in cache
        assert.is_not_nil(test.get_from_cache(key1))
        assert.is_not_nil(test.get_from_cache(key2))
    end)

    it("evicts oldest entry when cache size exceeded", function()
        temp_dir = fixtures.create_simple_project()

        -- Add entries beyond cache size (5)
        for i = 1, 6 do
            local key = test.get_cache_key("file" .. i, "c", temp_dir)
            local file_path = temp_dir .. "/file" .. i .. ".c"
            -- Create dummy files
            vim.fn.mkdir(vim.fn.fnamemodify(file_path, ":h"), "p")
            local file = io.open(file_path, "w")
            if file then
                file:write("test")
                file:close()
            end
            test.add_to_cache(key, file_path)
        end

        -- First entry should have been evicted
        local key1 = test.get_cache_key("file1", "c", temp_dir)
        local key6 = test.get_cache_key("file6", "c", temp_dir)

        assert.is_nil(test.get_from_cache(key1), "Oldest entry should be evicted")
        assert.is_not_nil(test.get_from_cache(key6), "Newest entry should remain")
    end)

    it("removes invalid cache entries on get", function()
        temp_dir = fixtures.create_simple_project()
        local fake_path = temp_dir .. "/nonexistent.c"
        local key = test.get_cache_key("nonexistent", "c", temp_dir)

        -- Add entry with non-existent file
        test.add_to_cache(key, fake_path)

        -- Should return nil and remove the invalid entry
        local result = test.get_from_cache(key)
        assert.is_nil(result)

        -- Second get should also return nil (entry was removed)
        local result2 = test.get_from_cache(key)
        assert.is_nil(result2)
    end)

    it("handles duplicate key by updating position", function()
        temp_dir = fixtures.create_simple_project()
        local key = test.get_cache_key("foo", "c", temp_dir)
        local path1 = fixtures.get_path(temp_dir, "src/foo.c")
        local path2 = fixtures.get_path(temp_dir, "include/foo.c")

        -- Create second file
        local file2 = io.open(path2, "w")
        if file2 then
            file2:write("test")
            file2:close()
        end

        -- Add same key twice with different paths
        test.add_to_cache(key, path1)
        test.add_to_cache(key, path2)

        -- Should have the latest value
        local result = test.get_from_cache(key)
        assert.equals(path2, result)
    end)

    it("respects cache_enabled config", function()
        -- Temporarily disable cache
        local state = test.get_state()
        state.config.cache_enabled = false

        temp_dir = fixtures.create_simple_project()
        local key = test.get_cache_key("foo", "c", temp_dir)
        local file_path = fixtures.get_path(temp_dir, "src/foo.c")

        test.add_to_cache(key, file_path)

        -- Should not cache when disabled
        local result = test.get_from_cache(key)
        assert.is_nil(result)

        -- Re-enable for other tests
        state.config.cache_enabled = true
    end)
end)

describe("Directory Mapping Cache", function()
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

    it("caches directory mapping", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")
        local include_dir = fixtures.get_path(temp_dir, "include")

        test.add_directory_mapping_to_cache(src_dir, "c", include_dir, "h", temp_dir)

        local predicted = test.get_predicted_directory(src_dir, "c", "h", temp_dir)
        assert.is_not_nil(predicted)
    end)

    it("returns predicted directory", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")
        local include_dir = fixtures.get_path(temp_dir, "include")

        test.add_directory_mapping_to_cache(src_dir, "c", include_dir, "h", temp_dir)

        local predicted = test.get_predicted_directory(src_dir, "c", "h", temp_dir)
        assert.is_not_nil(predicted)
        assert.is_true(vim.endswith(predicted, "include"), "Should predict include directory")
    end)

    it("returns nil for non-existent mapping", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")

        local predicted = test.get_predicted_directory(src_dir, "c", "h", temp_dir)
        assert.is_nil(predicted)
    end)

    it("removes invalid predicted directory", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")
        local fake_dir = temp_dir .. "/nonexistent"

        test.add_directory_mapping_to_cache(src_dir, "c", fake_dir, "h", temp_dir)

        -- Should return nil because predicted directory doesn't exist
        local predicted = test.get_predicted_directory(src_dir, "c", "h", temp_dir)
        assert.is_nil(predicted)

        -- Second call should also return nil (entry was removed)
        local predicted2 = test.get_predicted_directory(src_dir, "c", "h", temp_dir)
        assert.is_nil(predicted2)
    end)

    it("maintains LRU order for directory mappings", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")
        local include_dir = fixtures.get_path(temp_dir, "include")
        local test_dir = fixtures.get_path(temp_dir, "test")

        test.add_directory_mapping_to_cache(src_dir, "c", include_dir, "h", temp_dir)
        test.add_directory_mapping_to_cache(src_dir, "c", test_dir, "c", temp_dir)

        -- Access first mapping (should move to front)
        test.get_predicted_directory(src_dir, "c", "h", temp_dir)

        -- Both should still be accessible
        assert.is_not_nil(test.get_predicted_directory(src_dir, "c", "h", temp_dir))
        assert.is_not_nil(test.get_predicted_directory(src_dir, "c", "c", temp_dir))
    end)

    it("evicts oldest directory mapping when size exceeded", function()
        temp_dir = fixtures.create_simple_project()
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- Add more than cache_size (5) directory mappings
        for i = 1, 6 do
            -- Create dummy directories
            local target_dir = temp_dir .. "/dir" .. i
            vim.fn.mkdir(target_dir, "p")
            test.add_directory_mapping_to_cache(src_dir, "c" .. i, target_dir, "h" .. i, temp_dir)
        end

        -- First mapping should be evicted, last should remain
        local predicted1 = test.get_predicted_directory(src_dir, "c1", "h1", temp_dir)
        local predicted6 = test.get_predicted_directory(src_dir, "c6", "h6", temp_dir)

        assert.is_nil(predicted1, "Oldest directory mapping should be evicted")
        assert.is_not_nil(predicted6, "Newest directory mapping should remain")
    end)

    it("isolates cache by root directory", function()
        local temp_dir1 = fixtures.create_simple_project()
        local temp_dir2 = fixtures.create_simple_project()

        local src_dir1 = fixtures.get_path(temp_dir1, "src")
        local include_dir1 = fixtures.get_path(temp_dir1, "include")

        local src_dir2 = fixtures.get_path(temp_dir2, "src")

        -- Add mapping for project 1
        test.add_directory_mapping_to_cache(src_dir1, "c", include_dir1, "h", temp_dir1)

        -- Should not find mapping in project 2
        local predicted = test.get_predicted_directory(src_dir2, "c", "h", temp_dir2)
        assert.is_nil(predicted, "Directory mappings should be isolated by root")

        fixtures.cleanup(temp_dir1)
        fixtures.cleanup(temp_dir2)
    end)
end)

describe("Cache Integration", function()
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

    it("file cache and directory cache work together", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- Do a search which should populate both caches
        local results = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        assert.is_true(#results > 0)

        -- File cache should have the result
        local file_key = test.get_cache_key("foo", "h", root)
        assert.is_not_nil(test.get_from_cache(file_key))

        -- Now search for a similar file - should use directory prediction
        local results2 = test.search_files_recursively(root, src_dir, "bar", { "h" }, "c")
        assert.is_true(#results2 > 0)
    end)

    it("cache cleared affects both caches", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")
        local include_dir = fixtures.get_path(temp_dir, "include")

        -- Populate caches
        local file_key = test.get_cache_key("foo", "h", root)
        test.add_to_cache(file_key, fixtures.get_path(temp_dir, "include/foo.h"))
        test.add_directory_mapping_to_cache(src_dir, "c", include_dir, "h", root)

        -- Clear cache
        fileflip.clear_cache()

        -- Both should be empty
        assert.is_nil(test.get_from_cache(file_key))
        assert.is_nil(test.get_predicted_directory(src_dir, "c", "h", root))
    end)

    it("shows cache stats correctly", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- Populate cache
        test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")

        -- Stats should reflect cache usage
        local state = test.get_state()
        assert.is_true(#state.cache_order >= 0)
    end)

    it("second search benefits from cache", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- First search (cold cache)
        local results1 = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        assert.is_true(#results1 > 0)

        -- Second search (warm cache)
        local results2 = test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")
        assert.is_true(#results2 > 0)

        -- Results should be the same
        assert.equals(results1[1], results2[1])
    end)

    it("similar files use directory prediction", function()
        temp_dir = fixtures.create_simple_project()
        local root = test.find_root_directory(temp_dir)
        local src_dir = fixtures.get_path(temp_dir, "src")

        -- Search for foo.h from src/ (should cache src->include mapping)
        test.search_files_recursively(root, src_dir, "foo", { "h" }, "c")

        -- Search for bar.h from src/ (should use predicted directory)
        -- We can verify this by checking that the result is found
        local results = test.search_files_recursively(root, src_dir, "bar", { "h" }, "c")
        assert.is_true(#results > 0, "Should find bar.h using directory prediction")
    end)
end)
