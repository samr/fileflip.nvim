local M = {}

-----------------
-- Default config
--
local default_config = {
    -- Extension mappings: source extension -> list of target extensions
    extension_maps = {
        -- C/C++
        c = { "h", "hpp", "hxx" },
        cc = { "h", "hpp", "hxx" },
        cpp = { "h", "hpp", "hxx" },
        cxx = { "h", "hpp", "hxx" },
        cu = { "cuh" },

        h = { "c", "cc", "cpp", "cxx" },
        hpp = { "c", "cc", "cpp", "cxx" },
        hxx = { "c", "cc", "cpp", "cxx" },
        cuh = { "cu" },

        -- JavaScript/TypeScript
        js = { "ts", "jsx", "tsx" },
        ts = { "js", "jsx", "tsx" },
        jsx = { "js", "ts", "tsx" },
        tsx = { "js", "ts", "jsx" },

        -- Python
        py = { "pyi", "pyx" },
        pyi = { "py" },
        pyx = { "py" },

        -- Web files
        html = { "css", "js", "ts" },
        css = { "html", "scss", "sass" },
        scss = { "css", "html" },
        sass = { "css", "html" },
    },

    -- Prefix/suffix mappings: prefix/suffix -> list of possible prefix/suffixes
    prefix_suffix_maps = {
        -- Test file patterns
        ["_test"] = { "" }, -- suffix
        ["test_/"] = { "" }, -- prefix
        ["_spec"] = { "" },
        [".test"] = { "" },
        [".spec"] = { "" },

        -- Implementation patterns
        ["_impl"] = { "" },
        ["_implementation"] = { "" },
        [".impl"] = { "" },

        -- Mock patterns
        ["_mock"] = { "" },
        [".mock"] = { "" },

        -- Collected mapping the other way.
        [""] = {
            "_test",
            "test_/",
            "_spec",
            ".test",
            ".spec",
            "_impl",
            "_implementation",
            ".impl",
            "_mock",
            ".mock",
        },
    },

    -- Root directory marker files (plugin won't search above directories containing these)
    root_markers = {
        ".git",
        ".svn",
        ".hg",
        ".idea",
        ".vscode",
        "Makefile",
        "CMakeLists.txt",
        "Cargo.toml",
        "package.json",
        "LICENSE",
        "LICENSE.md",
    },

    -- Maximum depth to search upward from current file
    max_search_depth = 10,

    -- Cache settings
    cache_enabled = true,
    cache_size = 10000,

    -- Whether to ignore .filefliprc files, when true will not autoload or parse them.
    ignore_filefliprc = false,

    -- Whether to autoload the file based on the buffer. When false, it will only load once on startup based on the
    -- current working directory.
    autoload_filefliprc = true,
}

---------------
-- Plugin state
--
local config = {}
local file_cache = {}
local cache_order = {}
local directory_mapping_cache = {}
local dir_cache_order = {}

--------------------
-- Utility functions
--
local function get_file_parts(filepath)
    local basename = vim.fn.fnamemodify(filepath, ":t:r")
    local extension = vim.fn.fnamemodify(filepath, ":e")
    local directory = vim.fn.fnamemodify(filepath, ":h")
    return basename, extension, directory
end

local function find_root_directory(start_dir)
    local current_dir = start_dir
    local depth = 0

    while depth < config.max_search_depth do
        -- Check if current directory contains any root markers
        for _, marker in ipairs(config.root_markers) do
            local marker_path = current_dir .. "/" .. marker
            if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
                return current_dir
            end
        end

        -- Move up one directory
        local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
        if parent_dir == current_dir then
            -- Reached filesystem root
            break
        end

        current_dir = parent_dir
        depth = depth + 1
    end

    return start_dir -- Return original directory if no root found
end

local function get_cache_key(basename, extension, root_dir)
    return root_dir .. ":" .. basename .. "." .. extension
end

local function add_to_cache(key, filepath)
    if not config.cache_enabled then
        return
    end

    -- Remove if already exists to update order
    for i, cached_key in ipairs(cache_order) do
        if cached_key == key then
            table.remove(cache_order, i)
            break
        end
    end

    -- Add to front of cache
    table.insert(cache_order, 1, key)
    file_cache[key] = filepath

    -- Maintain cache size limit
    while #cache_order > config.cache_size do
        local old_key = table.remove(cache_order)
        file_cache[old_key] = nil
    end
end

local function get_directory_mapping_key(source_dir, source_ext, target_ext, root_dir)
    local relative_source = vim.fn.fnamemodify(source_dir, ":p"):gsub("^" .. vim.fn.fnamemodify(root_dir, ":p"), "")
    return root_dir .. ":" .. relative_source .. ":" .. source_ext .. "->" .. target_ext
end

local function add_directory_mapping_to_cache(source_dir, source_ext, target_dir, target_ext, root_dir)
    if not config.cache_enabled then
        return
    end

    local key = get_directory_mapping_key(source_dir, source_ext, target_ext, root_dir)
    local relative_target = vim.fn.fnamemodify(target_dir, ":p"):gsub("^" .. vim.fn.fnamemodify(root_dir, ":p"), "")

    -- Remove if already exists to update order
    for i, cached_key in ipairs(dir_cache_order) do
        if cached_key == key then
            table.remove(dir_cache_order, i)
            break
        end
    end

    -- Add to front of cache
    table.insert(dir_cache_order, 1, key)
    directory_mapping_cache[key] = relative_target

    -- Maintain cache size limit
    while #dir_cache_order > config.cache_size do
        local old_key = table.remove(dir_cache_order)
        directory_mapping_cache[old_key] = nil
    end
end

local function get_from_cache(key)
    if not config.cache_enabled then
        return nil
    end

    local cached_path = file_cache[key]
    if cached_path and vim.fn.filereadable(cached_path) == 1 then
        -- Move to front of cache (LRU)
        for i, cached_key in ipairs(cache_order) do
            if cached_key == key then
                table.remove(cache_order, i)
                table.insert(cache_order, 1, key)
                break
            end
        end
        return cached_path
    end

    -- Remove invalid cache entry
    if cached_path then
        file_cache[key] = nil
        for i, cached_key in ipairs(cache_order) do
            if cached_key == key then
                table.remove(cache_order, i)
                break
            end
        end
    end

    return nil
end

local function get_predicted_directory(source_dir, source_ext, target_ext, root_dir)
    if not config.cache_enabled then
        return nil
    end

    local key = get_directory_mapping_key(source_dir, source_ext, target_ext, root_dir)
    local cached_relative_dir = directory_mapping_cache[key]

    if cached_relative_dir then
        -- Move to front of cache (LRU)
        for i, cached_key in ipairs(dir_cache_order) do
            if cached_key == key then
                table.remove(dir_cache_order, i)
                table.insert(dir_cache_order, 1, key)
                break
            end
        end

        -- Convert relative path back to absolute
        local predicted_dir = vim.fn.fnamemodify(root_dir, ":p") .. cached_relative_dir
        predicted_dir = vim.fn.fnamemodify(predicted_dir, ":p:h") -- Normalize path

        -- Verify directory exists
        if vim.fn.isdirectory(predicted_dir) == 1 then
            return predicted_dir
        else
            -- Remove invalid cache entry
            directory_mapping_cache[key] = nil
            for i, cached_key in ipairs(dir_cache_order) do
                if cached_key == key then
                    table.remove(dir_cache_order, i)
                    break
                end
            end
        end
    end

    return nil
end

local function search_file_in_directory(directory, basename, extension)
    local filename = basename .. "." .. extension
    local filepath = directory .. "/" .. filename

    if vim.fn.filereadable(filepath) == 1 then
        return filepath
    end

    return nil
end

local function get_prefix_and_suffix(entry)
    if entry == nil or entry == "" then
        return "", ""
    end
    local prefix, suffix = string.match(entry, "([^/]*)/(.*)")
    if prefix ~= nil and suffix ~= nil then
        return prefix, suffix
    end
    prefix = string.match(entry, "([^/]+)/")
    if prefix ~= nil then
        return prefix, ""
    end
    suffix = string.match(entry, "/(.+)")
    if suffix ~= nil then
        return "", suffix
    end

    return "", entry
end

local function get_basename_parts(basename)
    for pattern, _ in pairs(config.prefix_suffix_maps) do
        prefix, suffix = get_prefix_and_suffix(pattern)
        local core_basename = basename
        if prefix ~= "" and vim.startswith(basename, prefix) then
            core_basename = core_basename:sub(#prefix + 1)
        end
        if suffix ~= "" and vim.endswith(basename, suffix) then
            core_basename = core_basename:sub(1, -(#suffix + 1))
        end
        if core_basename ~= basename then
            return prefix, core_basename, suffix
        end
    end
    return "", basename, ""
end

local function generate_alternative_basenames(current_prefix, core_basename, current_suffix, extension)
    local alternatives = {}
    local patterns = config.prefix_suffix_maps[current_prefix .. "/" .. current_suffix]
        or config.prefix_suffix_maps[current_prefix .. "/"]
        or config.prefix_suffix_maps["/" .. current_suffix]
        or config.prefix_suffix_maps[current_suffix]
        or {}

    -- Add alternatives based on current suffix
    for _, target_pattern in ipairs(patterns) do
        target_prefix, target_suffix = get_prefix_and_suffix(target_pattern)
        local alt_basename = target_prefix .. core_basename .. target_suffix
        table.insert(alternatives, alt_basename)
    end

    -- If no specific patterns found, try common alternatives
    if #alternatives == 0 then
        if current_suffix == "" then
            -- From base file, try test variations
            table.insert(alternatives, core_basename .. "_test")
            table.insert(alternatives, core_basename .. "_spec")
            table.insert(alternatives, core_basename .. "_impl")
            table.insert(alternatives, core_basename .. "_mock")
        else
            -- From suffixed file, try base file
            table.insert(alternatives, core_basename)
        end
    end

    return alternatives
end

local function search_alternative_files(
    root_dir,
    start_dir,
    alternative_basenames,
    extension,
    current_prefix,
    core_basename,
    current_suffix
)
    local found_files = {}

    -- First, check cache for each alternative basename
    for _, alt_basename in ipairs(alternative_basenames) do
        local cache_key = get_cache_key(alt_basename, extension, root_dir)
        local cached_path = get_from_cache(cache_key)
        if cached_path then
            table.insert(found_files, cached_path)
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Second, check directory mapping cache for predicted locations
    for _, alt_basename in ipairs(alternative_basenames) do
        local alt_prefix, _, alt_suffix = get_basename_parts(alt_basename)
        local predicted_dir = get_predicted_directory(
            start_dir,
            current_prefix .. "|" .. current_suffix .. "." .. extension,
            alt_prefix .. "|" .. alt_suffix .. "." .. extension,
            root_dir
        )
        if predicted_dir then
            local found_file = search_file_in_directory(predicted_dir, alt_basename, extension)
            if found_file then
                -- Cache both the file and confirm the directory mapping
                local cache_key = get_cache_key(alt_basename, extension, root_dir)
                add_to_cache(cache_key, found_file)
                add_directory_mapping_to_cache(
                    start_dir,
                    current_prefix .. "|" .. current_suffix .. "." .. extension,
                    predicted_dir,
                    alt_prefix .. "|" .. alt_suffix .. "." .. extension,
                    root_dir
                )
                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Third, search upward in the directory tree
    local search_dirs = {}
    local current_dir = start_dir

    while true do
        table.insert(search_dirs, current_dir)

        if current_dir == root_dir then
            break
        end

        local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
        if parent_dir == current_dir then
            break
        end

        current_dir = parent_dir

        if not vim.startswith(current_dir, root_dir) then
            break
        end
    end

    -- Search in each directory going up the tree
    for _, dir in ipairs(search_dirs) do
        for _, alt_basename in ipairs(alternative_basenames) do
            local found_file = search_file_in_directory(dir, alt_basename, extension)
            if found_file then
                local cache_key = get_cache_key(alt_basename, extension, root_dir)
                add_to_cache(cache_key, found_file)

                -- Cache the directory mapping for future predictions
                local found_dir = vim.fn.fnamemodify(found_file, ":h")
                local alt_prefix, _, alt_suffix = get_basename_parts(alt_basename)
                add_directory_mapping_to_cache(
                    start_dir,
                    current_prefix .. "|" .. current_suffix .. "." .. extension,
                    found_dir,
                    alt_prefix .. "|" .. alt_suffix .. "." .. extension,
                    root_dir
                )

                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Fourth, do a full recursive search from root
    for _, alt_basename in ipairs(alternative_basenames) do
        local pattern = "**/" .. alt_basename .. "." .. extension
        local glob_result = vim.fn.globpath(root_dir, pattern, false, true)

        for _, file_path in ipairs(glob_result) do
            if vim.fn.filereadable(file_path) == 1 then
                local cache_key = get_cache_key(alt_basename, extension, root_dir)
                add_to_cache(cache_key, file_path)

                -- Cache the directory mapping for future predictions
                local found_dir = vim.fn.fnamemodify(file_path, ":h")
                local alt_prefix, _, alt_suffix = get_basename_parts(alt_basename)
                add_directory_mapping_to_cache(
                    start_dir,
                    current_prefix .. "|" .. current_suffix .. "." .. extension,
                    found_dir,
                    alt_prefix .. "|" .. alt_suffix .. "." .. extension,
                    root_dir
                )

                table.insert(found_files, file_path)
            end
        end
    end

    return found_files
end

local function search_files_recursively_in_tree(root_dir, basename, target_extensions)
    local found_files = {}

    -- Use vim's globpath to recursively search for files
    for _, ext in ipairs(target_extensions) do
        local pattern = "**/" .. basename .. "." .. ext
        local glob_result = vim.fn.globpath(root_dir, pattern, false, true)

        for _, file_path in ipairs(glob_result) do
            if vim.fn.filereadable(file_path) == 1 then
                table.insert(found_files, file_path)
            end
        end
    end

    return found_files
end

local function search_files_recursively(root_dir, start_dir, basename, target_extensions, source_extension)
    local found_files = {}

    -- First, check cache for each target extension
    for _, ext in ipairs(target_extensions) do
        local cache_key = get_cache_key(basename, ext, root_dir)
        local cached_path = get_from_cache(cache_key)
        if cached_path then
            table.insert(found_files, cached_path)
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Second, check directory mapping cache for predicted locations
    for _, ext in ipairs(target_extensions) do
        local predicted_dir = get_predicted_directory(start_dir, source_extension, ext, root_dir)
        if predicted_dir then
            local found_file = search_file_in_directory(predicted_dir, basename, ext)
            if found_file then
                -- Cache both the file and confirm the directory mapping
                local cache_key = get_cache_key(basename, ext, root_dir)
                add_to_cache(cache_key, found_file)
                add_directory_mapping_to_cache(start_dir, source_extension, predicted_dir, ext, root_dir)
                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Third, search upward in the directory tree (original behavior)
    local search_dirs = {}
    local current_dir = start_dir

    while true do
        table.insert(search_dirs, current_dir)

        -- Stop if we've reached the root directory
        if current_dir == root_dir then
            break
        end

        -- Move up one directory
        local parent_dir = vim.fn.fnamemodify(current_dir, ":h")
        if parent_dir == current_dir then
            -- Reached filesystem root
            break
        end

        current_dir = parent_dir

        -- Safety check to not go above root
        if not vim.startswith(current_dir, root_dir) then
            break
        end
    end

    -- Search in each directory going up the tree
    for _, dir in ipairs(search_dirs) do
        for _, ext in ipairs(target_extensions) do
            local found_file = search_file_in_directory(dir, basename, ext)
            if found_file then
                -- Cache the result
                local cache_key = get_cache_key(basename, ext, root_dir)
                add_to_cache(cache_key, found_file)

                -- Cache the directory mapping for future predictions
                local found_dir = vim.fn.fnamemodify(found_file, ":h")
                add_directory_mapping_to_cache(start_dir, source_extension, found_dir, ext, root_dir)

                table.insert(found_files, found_file)
            end
        end
    end

    if #found_files > 0 then
        return found_files
    end

    -- Fourth, if nothing found in upward search, do a full recursive search from root
    local recursive_files = search_files_recursively_in_tree(root_dir, basename, target_extensions)
    for _, found_file in ipairs(recursive_files) do
        -- Cache the result
        local file_ext = vim.fn.fnamemodify(found_file, ":e")
        local cache_key = get_cache_key(basename, file_ext, root_dir)
        add_to_cache(cache_key, found_file)

        -- Cache the directory mapping for future predictions
        local found_dir = vim.fn.fnamemodify(found_file, ":h")
        add_directory_mapping_to_cache(start_dir, source_extension, found_dir, file_ext, root_dir)

        table.insert(found_files, found_file)
    end

    return found_files
end

---------------------------------
-- Functions to load config files
--

-- Finds the .filefliprc file, if it exists, by traversing up directories
local function find_rc_file(start_path)
    local current_path = start_path or vim.fn.getcwd()

    -- Normalize path separators for cross-platform compatibility
    current_path = vim.fn.fnamemodify(current_path, ":p")

    while current_path ~= "/" and current_path ~= "" do
        local rc_path = current_path .. "/.filefliprc"

        -- Check if .filefliprc exists and is readable
        if vim.fn.filereadable(rc_path) == 1 then
            return rc_path
        end

        -- Move up one directory
        local parent = vim.fn.fnamemodify(current_path, ":h")

        -- Prevent infinite loop on Windows/systems where parent == current
        if parent == current_path then
            break
        end

        current_path = parent
    end

    return nil
end

-- Removes comments from content
local function remove_comments(content)
    local result = ""
    local i = 1
    local in_string = false
    local string_char = nil

    while i <= #content do
        local char = content:sub(i, i)
        local next_char = content:sub(i + 1, i + 1)

        -- Handle string boundaries
        if not in_string and (char == '"' or char == "'") then
            in_string = true
            string_char = char
            result = result .. char
            i = i + 1
        elseif in_string and char == string_char then
            -- Check if it's escaped
            local escape_count = 0
            local j = i - 1
            while j >= 1 and content:sub(j, j) == "\\" do
                escape_count = escape_count + 1
                j = j - 1
            end

            if escape_count % 2 == 0 then -- Not escaped
                in_string = false
                string_char = nil
            end
            result = result .. char
            i = i + 1
        elseif not in_string and char == "-" and next_char == "-" then
            -- Found inline comment, skip to end of line
            local newline = content:find("\n", i)
            if newline then
                result = result .. "\n" -- Keep the newline
                i = newline + 1
            else
                break -- End of file
            end
        elseif not in_string and char == "#" then
            -- Found # comment, skip to end of line
            local newline = content:find("\n", i)
            if newline then
                result = result .. "\n" -- Keep the newline
                i = newline + 1
            else
                break -- End of file
            end
        else
            result = result .. char
            i = i + 1
        end
    end

    return result
end

-- Parses the .filefliprc file with support for nested tables and multi-line values
local function parse_rc_file(file_path)
    local settings = {}
    local file = io.open(file_path, "r")

    if not file then
        vim.notify("Error: Could not open " .. file_path, vim.log.levels.ERROR)
        return nil
    end

    local content = file:read("*all")
    file:close()

    -- Remove both -- and # comments while preserving string contents
    content = remove_comments(content)

    local i = 1
    while i <= #content do
        -- Skip whitespace
        local whitespace_end = content:find("[^%s]", i)
        if not whitespace_end then
            break
        end
        i = whitespace_end

        -- Find key=value pattern
        local key_start, key_end = content:find("([%w_]+)%s*=", i)
        if not key_start then
            break
        end

        local key = content:sub(key_start, key_end - 1):match("([%w_]+)")
        i = key_end + 1

        -- Skip whitespace after =
        local value_start = content:find("[^%s]", i)
        if not value_start then
            break
        end
        i = value_start

        local value, value_end = parse_value(content, i)
        if value ~= nil then
            settings[key] = value
            i = value_end + 1
        else
            -- Skip to next line if parsing failed
            local next_line = content:find("\n", i)
            if next_line then
                i = next_line + 1
            else
                break
            end
        end
    end

    return settings
end

-- Parses a value (string, number, boolean, or table)
function parse_value(content, start_pos)
    local i = start_pos

    -- Skip leading whitespace
    local value_start = content:find("[^%s]", i)
    if not value_start then
        return nil, start_pos
    end
    i = value_start

    local char = content:sub(i, i)

    -- Parse table/array
    if char == "{" then
        return parse_table(content, i)
    end

    -- Parse quoted string
    if char == '"' or char == "'" then
        return parse_quoted_string(content, i)
    end

    -- Parse unquoted value (boolean, number, or string)
    return parse_unquoted_value(content, i)
end

-- Parses table/array structures
function parse_table(content, start_pos)
    local i = start_pos + 1 -- skip opening {
    local result = {}
    local max_iterations = 1000 -- Safety limit
    local iterations = 0

    while i <= #content and iterations < max_iterations do
        iterations = iterations + 1

        -- Skip whitespace and newlines
        local next_char_pos = content:find("[^%s\n]", i)
        if not next_char_pos then
            break
        end
        i = next_char_pos

        local char = content:sub(i, i)

        -- End of table
        if char == "}" then
            return result, i
        end

        -- Skip comma
        if char == "," then
            i = i + 1
        else
            local old_i = i -- Save position to detect infinite loops

            -- Check for key-value pair with brackets: ["key"] = value
            if char == "[" then
                local bracket_key_start, bracket_key_end, bracket_key =
                    content:find("%[%s*[\"']([^\"']*)[\"']%s*%]%s*=", i)
                if bracket_key_start == i then
                    i = bracket_key_end + 1

                    -- Parse the value
                    local value, value_end = parse_value(content, i)
                    if value ~= nil and value_end >= i then
                        result[bracket_key] = value
                        i = value_end + 1
                    else
                        -- Skip to next comma or closing brace
                        local next_comma = content:find(",", i)
                        local next_brace = content:find("}", i)
                        if next_comma and (not next_brace or next_comma < next_brace) then
                            i = next_comma + 1
                        elseif next_brace then
                            i = next_brace
                        else
                            break
                        end
                    end
                else
                    -- Not a valid bracket key-value pair, treat as array value
                    local value, value_end = parse_value(content, i)
                    if value ~= nil and value_end >= i then
                        table.insert(result, value)
                        i = value_end + 1
                    else
                        i = i + 1 -- Force advance if parsing fails
                    end
                end
            else
                -- Check for simple key = value (without brackets)
                local simple_key_start, simple_key_end, simple_key = content:find("([%w_]+)%s*=", i)
                if simple_key_start == i then
                    i = simple_key_end + 1

                    local value, value_end = parse_value(content, i)
                    if value ~= nil and value_end >= i then
                        result[simple_key] = value
                        i = value_end + 1
                    else
                        -- Skip to next comma or closing brace
                        local next_comma = content:find(",", i)
                        local next_brace = content:find("}", i)
                        if next_comma and (not next_brace or next_comma < next_brace) then
                            i = next_comma + 1
                        elseif next_brace then
                            i = next_brace
                        else
                            break
                        end
                    end
                else
                    -- Array-style value (no key)
                    local value, value_end = parse_value(content, i)
                    if value ~= nil and value_end >= i then
                        table.insert(result, value)
                        i = value_end + 1
                    else
                        i = i + 1 -- Force advance if parsing fails
                    end
                end
            end

            -- Safety check: if position hasn't advanced, force advancement
            if i == old_i then
                i = i + 1
            end
        end
    end

    if iterations >= max_iterations then
        vim.notify("Warning: Table parsing stopped due to potential infinite loop", vim.log.levels.WARN)
    end

    -- Return partial result if we didn't find closing brace
    return result, i
end

-- Parses quoted strings
function parse_quoted_string(content, start_pos)
    local quote_char = content:sub(start_pos, start_pos)
    local i = start_pos + 1
    local result = ""

    while i <= #content do
        local char = content:sub(i, i)

        if char == quote_char then
            return result, i
        elseif char == "\\" and i < #content then
            -- Handle escape sequences
            local next_char = content:sub(i + 1, i + 1)
            if next_char == "n" then
                result = result .. "\n"
            elseif next_char == "t" then
                result = result .. "\t"
            elseif next_char == "\\" then
                result = result .. "\\"
            elseif next_char == quote_char then
                result = result .. quote_char
            else
                result = result .. next_char
            end
            i = i + 2
        else
            result = result .. char
            i = i + 1
        end
    end

    return result, i
end

-- Parses unquoted values
function parse_unquoted_value(content, start_pos)
    local i = start_pos
    local result = ""

    -- Read until whitespace, comma, newline, or }
    while i <= #content do
        local char = content:sub(i, i)
        if char:match("[%s,}]") or char == "\n" then
            break
        end
        result = result .. char
        i = i + 1
    end

    -- Convert to appropriate type
    if result:lower() == "true" then
        return true, i - 1
    elseif result:lower() == "false" then
        return false, i - 1
    elseif result:match("^%-?%d+%.?%d*$") then
        return tonumber(result), i - 1
    else
        return result, i - 1
    end
end

-- Helper function to format values for display
local function format_value(value, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)

    if type(value) == "table" then
        local result = "{\n"
        for k, v in pairs(value) do
            local key_str = type(k) == "string" and '["' .. k .. '"]' or "[" .. tostring(k) .. "]"
            result = result .. spaces .. "  " .. key_str .. " = " .. format_value(v, indent + 1) .. ",\n"
        end
        result = result .. spaces .. "}"
        return result
    elseif type(value) == "string" then
        return '"' .. value .. '"'
    else
        return tostring(value)
    end
end

-- Loads and applies .fileflipc configuration
function M.load_config(path)
    local rc_path = find_rc_file(path)

    if rc_path then
        -- vim.notify("Found .filefliprc at: " .. rc_path, vim.log.levels.INFO)

        local file_settings = parse_rc_file(rc_path)
        if file_settings then
            -- Merge with global settings (file settings override global)
            for key, value in pairs(file_settings) do
                config[key] = value
                -- print(key .. " = " .. format_value(value))
            end

            -- vim.notify("Applied .filefliprc configuration", vim.log.levels.INFO)
            return true
        end
    else
        -- vim.notify("No .filefliprc file found", vim.log.levels.INFO)
    end

    return false
end

-- Shows current settings (with pretty printing for tables)
function M.show_config()
    print("Current FileFlip configuration settings:")
    for key, value in pairs(config) do
        print("  " .. key .. " = " .. format_value(value))
    end
end

---------------------------------
-- Functions that map to commands
--
function M.switch_file()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    -- Get target extensions for current file extension
    local target_extensions = config.extension_maps[extension]
    if not target_extensions or #target_extensions == 0 then
        vim.notify("No extension mappings found for ." .. extension, vim.log.levels.WARN)
        return
    end

    -- Find root directory
    local root_dir = find_root_directory(directory)

    -- Search for files
    local found_files = search_files_recursively(root_dir, directory, basename, target_extensions, extension)

    if #found_files == 0 then
        local ext_list = table.concat(target_extensions, ", ")
        vim.notify(
            "No files found with basename '" .. basename .. "' and extensions: " .. ext_list,
            vim.log.levels.INFO
        )
        return
    end

    -- Open the first found file
    local target_file = found_files[1]
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))

    -- Show notification with what was found
    if #found_files > 1 then
        vim.notify(
            "Switched to "
                .. vim.fn.fnamemodify(target_file, ":.")
                .. " ("
                .. (#found_files - 1)
                .. " other options available)",
            vim.log.levels.INFO
        )
    else
        vim.notify("Switched to " .. vim.fn.fnamemodify(target_file, ":."), vim.log.levels.INFO)
    end
end

function M.show_available_files()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    local target_extensions = config.extension_maps[extension]
    if not target_extensions or #target_extensions == 0 then
        vim.notify("No extension mappings found for ." .. extension, vim.log.levels.WARN)
        return
    end

    local root_dir = find_root_directory(directory)
    local found_files = search_files_recursively(root_dir, directory, basename, target_extensions, extension)

    if #found_files == 0 then
        local ext_list = table.concat(target_extensions, ", ")
        vim.notify(
            "No files found with basename '" .. basename .. "' and extensions: " .. ext_list,
            vim.log.levels.INFO
        )
        return
    end

    -- Display found files
    print("Available files for '" .. basename .. "':")
    for i, file in ipairs(found_files) do
        print(string.format("  %d. %s", i, vim.fn.fnamemodify(file, ":.")))
    end
end

function M.switch_file_alternative()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    -- Extract core basename and current suffix
    local current_prefix, core_basename, current_suffix = get_basename_parts(basename)

    -- Generate alternative basenames
    local alternative_basenames =
        generate_alternative_basenames(current_prefix, core_basename, current_suffix, extension)

    if #alternative_basenames == 0 then
        vim.notify("No alternative patterns found for '" .. basename .. "'", vim.log.levels.WARN)
        return
    end

    -- Find root directory
    local root_dir = find_root_directory(directory)

    -- Search for alternative files
    local found_files = search_alternative_files(
        root_dir,
        directory,
        alternative_basenames,
        extension,
        current_prefix,
        core_basename,
        current_suffix
    )

    if #found_files == 0 then
        local alt_list = table.concat(alternative_basenames, ", ")
        vim.notify("No alternative files found for basenames: " .. alt_list .. "." .. extension, vim.log.levels.INFO)
        return
    end

    -- Open the first found file
    local target_file = found_files[1]
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))

    -- Show notification with what was found
    if #found_files > 1 then
        vim.notify(
            "Switched to "
                .. vim.fn.fnamemodify(target_file, ":.")
                .. " ("
                .. (#found_files - 1)
                .. " other alternatives available)",
            vim.log.levels.INFO
        )
    else
        vim.notify("Switched to " .. vim.fn.fnamemodify(target_file, ":."), vim.log.levels.INFO)
    end
end

function M.show_alternative_files()
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        vim.notify("No file currently open", vim.log.levels.WARN)
        return
    end

    local basename, extension, directory = get_file_parts(current_file)

    if extension == "" then
        vim.notify("Current file has no extension", vim.log.levels.WARN)
        return
    end

    local current_prefix, core_basename, current_suffix = get_basename_parts(basename)
    local alternative_basenames =
        generate_alternative_basenames(current_prefix, core_basename, current_suffix, extension)

    if #alternative_basenames == 0 then
        vim.notify("No alternative patterns found for '" .. basename .. "'", vim.log.levels.WARN)
        return
    end

    local root_dir = find_root_directory(directory)
    local found_files = search_alternative_files(
        root_dir,
        directory,
        alternative_basenames,
        extension,
        current_prefix,
        core_basename,
        current_suffix
    )

    if #found_files == 0 then
        local alt_list = table.concat(alternative_basenames, ", ")
        vim.notify("No alternative files found for basenames: " .. alt_list .. "." .. extension, vim.log.levels.INFO)
        return
    end

    -- Display found files
    print("Alternative files for '" .. core_basename .. "' (current: " .. basename .. "  ." .. extension .. "):")
    for i, file in ipairs(found_files) do
        print(string.format("  %d. %s", i, vim.fn.fnamemodify(file, ":.")))
    end
end

function M.clear_cache()
    file_cache = {}
    cache_order = {}
    directory_mapping_cache = {}
    dir_cache_order = {}
    vim.notify("File cache and directory mappings cleared", vim.log.levels.INFO)
end

function M.show_cache_stats()
    local cache_count = #cache_order
    local dir_cache_count = #dir_cache_order
    local max_size = config.cache_size

    print(string.format("File Cache: %d/%d entries", cache_count, max_size))
    print(string.format("Directory Mapping Cache: %d/%d entries", dir_cache_count, max_size))

    if cache_count > 0 then
        print("Recent file cache entries:")
        for i = 1, math.min(3, cache_count) do
            local key = cache_order[i]
            local file = file_cache[key]
            print(string.format("  %s -> %s", key, vim.fn.fnamemodify(file, ":.")))
        end
    end

    if dir_cache_count > 0 then
        print("Recent directory mappings:")
        for i = 1, math.min(3, dir_cache_count) do
            local key = dir_cache_order[i]
            local dir = directory_mapping_cache[key]
            print(string.format("  %s -> %s", key, dir))
        end
    end
end

-------------------------------------
-- Setup command to function mappings
--
function M.setup(user_config)
    config = vim.tbl_extend("force", default_config, user_config or {})

    vim.api.nvim_create_user_command("FileFlipByExtension", M.switch_file, {
        desc = "Switch to related file based on extension mapping (e.g. foo.h <-> foo.cc)",
    })

    vim.api.nvim_create_user_command("FileFlipByPrefixSuffix", M.switch_file_alternative, {
        desc = "Switch to file based on prefix/suffix + basename patterns (e.g. foo.cc <-> foo_test.cc)",
    })

    vim.api.nvim_create_user_command("FileFlipByExtensionShow", M.show_available_files, {
        desc = "Show all available files for current basename based on extension mappings",
    })

    vim.api.nvim_create_user_command("FileFlipByPrefixSuffixShow", M.show_alternative_files, {
        desc = "Show all available files for current basename based on prefix/suffix mappings",
    })

    vim.api.nvim_create_user_command("FileFlipClearCache", M.clear_cache, {
        desc = "Clear the file switcher cache",
    })

    vim.api.nvim_create_user_command("FileFlipShowStats", M.show_cache_stats, {
        desc = "Show file cache statistics",
    })

    vim.api.nvim_create_user_command("FileFlipShowConfig", M.show_config, {
        desc = "Show .filefliprc configuration",
    })

    if not config.ignore_filefliprc then
        vim.api.nvim_create_user_command("FileFlipLoadConfig", function(opts)
            local path = opts.args and opts.args ~= "" and opts.args or nil
            M.load_config(path)
        end, {
            desc = "Load .foorc configuration",
            nargs = "?",
            complete = "dir",
        })

        if config.autoload_filefliprc then
            -- Auto-load configuration when entering a buffer
            vim.api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
                callback = function()
                    M.load_config()
                end,
                desc = "Auto-load .filefliprc configuration",
            })
        end

        -- Load configuration immediately
        M.load_config()
    end
end

return M
