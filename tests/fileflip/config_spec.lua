-- Tests for configuration and RC file parsing in fileflip.nvim

local fileflip = require("fileflip")
local fixtures = require("fixtures")

local test = fileflip._test

describe("remove_comments", function()
    it("removes -- style comments", function()
        local input = "cache_size = 100 -- this is a comment"
        local result = test.remove_comments(input)
        assert.is_true(result:match("cache_size = 100"))
        assert.is_false(result:match("this is a comment"))
    end)

    it("removes # style comments", function()
        local input = "cache_size = 100 # this is a comment"
        local result = test.remove_comments(input)
        assert.is_true(result:match("cache_size = 100"))
        assert.is_false(result:match("this is a comment"))
    end)

    it("preserves comments inside strings", function()
        local input = 'name = "foo -- bar"'
        local result = test.remove_comments(input)
        assert.is_true(result:match("foo %-%- bar"), "Should preserve -- inside string")
    end)

    it("handles multiple comments on different lines", function()
        local input = "a = 1 -- comment 1\nb = 2 -- comment 2"
        local result = test.remove_comments(input)
        assert.is_true(result:match("a = 1"))
        assert.is_true(result:match("b = 2"))
        assert.is_false(result:match("comment"))
    end)

    it("preserves newlines", function()
        local input = "a = 1 -- comment\nb = 2"
        local result = test.remove_comments(input)
        local line_count = select(2, result:gsub("\n", "\n"))
        assert.equals(1, line_count, "Should preserve newlines")
    end)
end)

describe("parse_unquoted_value", function()
    it("parses boolean true", function()
        local value, pos = test.parse_unquoted_value("true", 1)
        assert.equals(true, value)
        assert.is_number(pos)
    end)

    it("parses boolean false", function()
        local value, pos = test.parse_unquoted_value("false", 1)
        assert.equals(false, value)
        assert.is_number(pos)
    end)

    it("parses integer", function()
        local value, pos = test.parse_unquoted_value("42", 1)
        assert.equals(42, value)
        assert.is_number(pos)
    end)

    it("parses float", function()
        local value, pos = test.parse_unquoted_value("3.14", 1)
        assert.equals(3.14, value)
        assert.is_number(pos)
    end)

    it("parses negative number", function()
        local value, pos = test.parse_unquoted_value("-100", 1)
        assert.equals(-100, value)
    end)

    it("parses unquoted string", function()
        local value, pos = test.parse_unquoted_value("test", 1)
        assert.equals("test", value)
    end)

    it("stops at whitespace", function()
        local value, pos = test.parse_unquoted_value("test more", 1)
        assert.equals("test", value)
    end)

    it("stops at comma", function()
        local value, pos = test.parse_unquoted_value("test,", 1)
        assert.equals("test", value)
    end)
end)

describe("parse_quoted_string", function()
    it("parses double quoted string", function()
        local value, pos = test.parse_quoted_string('"hello"', 1)
        assert.equals("hello", value)
    end)

    it("parses single quoted string", function()
        local value, pos = test.parse_quoted_string("'hello'", 1)
        assert.equals("hello", value)
    end)

    it("handles escaped quotes", function()
        local value, pos = test.parse_quoted_string('"hello \\"world\\""', 1)
        assert.is_true(value:match('hello "world"'))
    end)

    it("handles escape sequences", function()
        local value, pos = test.parse_quoted_string('"line1\\nline2"', 1)
        assert.is_true(value:match("\n"), "Should convert \\n to newline")
    end)

    it("handles empty string", function()
        local value, pos = test.parse_quoted_string('""', 1)
        assert.equals("", value)
    end)
end)

describe("parse_table", function()
    it("parses simple array", function()
        local value, pos = test.parse_table('{ "a", "b", "c" }', 1)
        assert.is_table(value)
        assert.equals(3, #value)
        assert.equals("a", value[1])
        assert.equals("b", value[2])
        assert.equals("c", value[3])
    end)

    it("parses simple key-value pairs", function()
        local value, pos = test.parse_table('{ a = 1, b = 2 }', 1)
        assert.is_table(value)
        assert.equals(1, value.a)
        assert.equals(2, value.b)
    end)

    it("parses nested tables", function()
        local value, pos = test.parse_table('{ a = { b = 1 } }', 1)
        assert.is_table(value)
        assert.is_table(value.a)
        assert.equals(1, value.a.b)
    end)

    it("parses bracket key syntax", function()
        local value, pos = test.parse_table('{ ["key"] = "value" }', 1)
        assert.is_table(value)
        assert.equals("value", value.key)
    end)

    it("parses mixed array and table", function()
        local value, pos = test.parse_table('{ "first", a = 1 }', 1)
        assert.is_table(value)
        assert.equals("first", value[1])
        assert.equals(1, value.a)
    end)

    it("handles empty table", function()
        local value, pos = test.parse_table('{}', 1)
        assert.is_table(value)
        assert.equals(0, #value)
    end)

    it("handles multiline tables", function()
        local input = [[{
            a = 1,
            b = 2
        }]]
        local value, pos = test.parse_table(input, 1)
        assert.is_table(value)
        assert.equals(1, value.a)
        assert.equals(2, value.b)
    end)
end)

describe("parse_rc_file", function()
    local temp_dir

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("parses simple key-value pairs", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_content = "cache_size = 100\nmax_search_depth = 5"
        local rc_path = fixtures.create_rc_file(temp_dir, rc_content)

        local settings = test.parse_rc_file(rc_path)
        assert.is_not_nil(settings)
        assert.equals(100, settings.cache_size)
        assert.equals(5, settings.max_search_depth)
    end)

    it("parses table values", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_content = 'extension_maps = { h = { "c" } }'
        local rc_path = fixtures.create_rc_file(temp_dir, rc_content)

        local settings = test.parse_rc_file(rc_path)
        assert.is_not_nil(settings)
        assert.is_table(settings.extension_maps)
        assert.is_table(settings.extension_maps.h)
        assert.equals("c", settings.extension_maps.h[1])
    end)

    it("handles comments correctly", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_content = [[
-- This is a comment
cache_size = 100 -- inline comment
# Another comment style
max_search_depth = 5
]]
        local rc_path = fixtures.create_rc_file(temp_dir, rc_content)

        local settings = test.parse_rc_file(rc_path)
        assert.is_not_nil(settings)
        assert.equals(100, settings.cache_size)
        assert.equals(5, settings.max_search_depth)
    end)

    it("parses boolean values", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_content = "cache_enabled = false\nautoload_filefliprc = true"
        local rc_path = fixtures.create_rc_file(temp_dir, rc_content)

        local settings = test.parse_rc_file(rc_path)
        assert.is_not_nil(settings)
        assert.equals(false, settings.cache_enabled)
        assert.equals(true, settings.autoload_filefliprc)
    end)

    it("handles nested tables", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_content = [[
prefix_suffix_maps = {
    ["_test"] = { "" },
    [""] = { "_test" }
}
]]
        local rc_path = fixtures.create_rc_file(temp_dir, rc_content)

        local settings = test.parse_rc_file(rc_path)
        assert.is_not_nil(settings)
        assert.is_table(settings.prefix_suffix_maps)
        assert.is_table(settings.prefix_suffix_maps["_test"])
        assert.equals("", settings.prefix_suffix_maps["_test"][1])
    end)

    it("returns nil for non-existent file", function()
        local settings = test.parse_rc_file("/nonexistent/.filefliprc")
        assert.is_nil(settings)
    end)

    it("handles empty file", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_path = fixtures.create_rc_file(temp_dir, "")

        local settings = test.parse_rc_file(rc_path)
        assert.is_table(settings)
    end)

    it("handles multiline values", function()
        temp_dir = vim.fn.tempname()
        vim.fn.mkdir(temp_dir, "p")
        local rc_content = [[
extension_maps = {
    h = { "c", "cc", "cpp" },
    c = { "h" }
}
]]
        local rc_path = fixtures.create_rc_file(temp_dir, rc_content)

        local settings = test.parse_rc_file(rc_path)
        assert.is_not_nil(settings)
        assert.is_table(settings.extension_maps)
        assert.equals(3, #settings.extension_maps.h)
    end)
end)

describe("find_rc_file", function()
    local temp_dir

    after_each(function()
        if temp_dir then
            fixtures.cleanup(temp_dir)
            temp_dir = nil
        end
    end)

    it("finds .filefliprc in current directory", function()
        temp_dir = fixtures.create_simple_project()
        fixtures.create_rc_file(temp_dir, "cache_size = 100")

        local rc_path = test.find_rc_file(temp_dir)
        assert.is_not_nil(rc_path)
        assert.is_true(vim.endswith(rc_path, ".filefliprc"))
    end)

    it("finds .filefliprc in parent directory", function()
        temp_dir = fixtures.create_simple_project()
        fixtures.create_rc_file(temp_dir, "cache_size = 100")
        local child_dir = fixtures.get_path(temp_dir, "src")

        local rc_path = test.find_rc_file(child_dir)
        assert.is_not_nil(rc_path)
        assert.is_true(vim.endswith(rc_path, ".filefliprc"))
    end)

    it("returns nil when no .filefliprc found", function()
        temp_dir = fixtures.create_simple_project()
        -- Don't create .filefliprc

        local rc_path = test.find_rc_file(temp_dir)
        assert.is_nil(rc_path)
    end)

    it("searches up directory tree", function()
        temp_dir = fixtures.create_complex_project()
        fixtures.create_rc_file(temp_dir, "cache_size = 100")
        local deep_dir = fixtures.get_path(temp_dir, "apps/web/src/components")

        local rc_path = test.find_rc_file(deep_dir)
        assert.is_not_nil(rc_path)
    end)
end)

describe("load_config", function()
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

    it("loads and applies RC file settings", function()
        temp_dir = fixtures.create_simple_project()
        fixtures.create_rc_file(temp_dir, "cache_size = 999")

        local success = fileflip.load_config(temp_dir)
        assert.is_true(success)

        local state = test.get_state()
        assert.equals(999, state.config.cache_size)
    end)

    it("RC file overrides global settings", function()
        temp_dir = fixtures.create_simple_project()
        fixtures.create_rc_file(temp_dir, "max_search_depth = 15")

        fileflip.load_config(temp_dir)

        local state = test.get_state()
        assert.equals(15, state.config.max_search_depth)
    end)

    it("returns false when no RC file found", function()
        temp_dir = fixtures.create_simple_project()
        -- No .filefliprc

        local success = fileflip.load_config(temp_dir)
        assert.is_false(success)
    end)

    it("merges settings correctly", function()
        temp_dir = fixtures.create_simple_project()
        -- Only override cache_size, other settings should remain default
        fixtures.create_rc_file(temp_dir, "cache_size = 123")

        fileflip.load_config(temp_dir)

        local state = test.get_state()
        assert.equals(123, state.config.cache_size)
        assert.is_not_nil(state.config.extension_maps, "Should preserve default extension_maps")
    end)
end)

describe("setup", function()
    before_each(function()
        test.reset_state()
    end)

    it("applies default config when no user config", function()
        fileflip.setup()

        local state = test.get_state()
        assert.is_not_nil(state.config)
        assert.is_table(state.config.extension_maps)
        assert.is_table(state.config.prefix_suffix_maps)
    end)

    it("merges user config with defaults", function()
        fileflip.setup({
            cache_size = 42,
        })

        local state = test.get_state()
        assert.equals(42, state.config.cache_size)
        assert.is_table(state.config.extension_maps, "Should have default extension_maps")
    end)

    it("user config replaces entire top-level values", function()
        fileflip.setup({
            extension_maps = {
                custom = { "test" },
            },
        })

        local state = test.get_state()
        assert.is_table(state.config.extension_maps)
        -- Should only have custom mapping, not defaults
        assert.is_nil(state.config.extension_maps.h, "Should replace entire extension_maps")
        assert.is_not_nil(state.config.extension_maps.custom)
    end)

    it("registers commands after setup", function()
        fileflip.setup()

        -- Commands should be registered
        local commands = vim.api.nvim_get_commands({})
        assert.is_not_nil(commands.FileFlipByExtension)
        assert.is_not_nil(commands.FileFlipByPrefixSuffix)
        assert.is_not_nil(commands.FileFlipClearCache)
    end)
end)
