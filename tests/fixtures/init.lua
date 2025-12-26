-- Test fixtures module
-- Provides helpers to create temporary test project structures

local M = {}

-- Creates a simple project structure for basic testing
-- Returns: temp_dir (string) - path to temporary directory
function M.create_simple_project()
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Create project structure:
    -- /tmp/xxx/
    --   .git/
    --   src/
    --     foo.c
    --     bar.c
    --   include/
    --     foo.h
    --     bar.h
    --   test/
    --     foo_test.c
    --     bar_test.c

    local structure = {
        ".git/HEAD",
        "src/foo.c",
        "src/bar.c",
        "include/foo.h",
        "include/bar.h",
        "test/foo_test.c",
        "test/bar_test.c",
    }

    for _, file_path in ipairs(structure) do
        local full_path = temp_dir .. "/" .. file_path
        local dir = vim.fn.fnamemodify(full_path, ":h")
        vim.fn.mkdir(dir, "p")

        -- Create empty file (directories already created by mkdir -p)
        if not vim.endswith(file_path, "/") then
            local file = io.open(full_path, "w")
            if file then
                file:write("-- test content for " .. file_path .. "\n")
                file:close()
            end
        end
    end

    return temp_dir
end

-- Creates a complex nested project structure
-- Returns: temp_dir (string) - path to temporary directory
function M.create_complex_project()
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Create complex structure:
    -- /tmp/xxx/
    --   .git/
    --   apps/
    --     web/
    --       src/
    --         components/
    --           Button.tsx
    --           Input.tsx
    --       test/
    --         components/
    --           Button.test.tsx
    --           Input.spec.tsx
    --     api/
    --       src/
    --         handlers/
    --           user.py
    --       test/
    --         handlers/
    --           test_user.py

    local structure = {
        ".git/HEAD",
        "apps/web/src/components/Button.tsx",
        "apps/web/src/components/Input.tsx",
        "apps/web/test/components/Button.test.tsx",
        "apps/web/test/components/Input.spec.tsx",
        "apps/api/src/handlers/user.py",
        "apps/api/test/handlers/test_user.py",
    }

    for _, file_path in ipairs(structure) do
        local full_path = temp_dir .. "/" .. file_path
        local dir = vim.fn.fnamemodify(full_path, ":h")
        vim.fn.mkdir(dir, "p")

        if not vim.endswith(file_path, "/") then
            local file = io.open(full_path, "w")
            if file then
                file:write("-- test content for " .. file_path .. "\n")
                file:close()
            end
        end
    end

    return temp_dir
end

-- Creates a project with multiple root markers
-- Returns: temp_dir (string) - path to temporary directory
function M.create_multi_root_project()
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Create structure with multiple potential root markers:
    -- /tmp/xxx/
    --   .git/
    --   package.json
    --   Makefile
    --   src/
    --     lib/
    --       util.js
    --   test/
    --     lib/
    --       util.test.js

    local structure = {
        ".git/HEAD",
        "package.json",
        "Makefile",
        "src/lib/util.js",
        "test/lib/util.test.js",
    }

    for _, file_path in ipairs(structure) do
        local full_path = temp_dir .. "/" .. file_path
        local dir = vim.fn.fnamemodify(full_path, ":h")
        vim.fn.mkdir(dir, "p")

        if not vim.endswith(file_path, "/") then
            local file = io.open(full_path, "w")
            if file then
                if vim.endswith(file_path, "package.json") then
                    file:write('{"name": "test-project"}\n')
                elseif vim.endswith(file_path, "Makefile") then
                    file:write("all:\n\techo 'test'\n")
                else
                    file:write("-- test content for " .. file_path .. "\n")
                end
                file:close()
            end
        end
    end

    return temp_dir
end

-- Creates a project with deep nesting (tests max search depth)
-- Returns: temp_dir (string) - path to temporary directory
function M.create_deep_project()
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Create very deep structure:
    -- /tmp/xxx/
    --   .git/
    --   a/b/c/d/e/f/g/h/i/j/
    --     deep.c
    --   include/
    --     deep.h

    local structure = {
        ".git/HEAD",
        "a/b/c/d/e/f/g/h/i/j/deep.c",
        "include/deep.h",
    }

    for _, file_path in ipairs(structure) do
        local full_path = temp_dir .. "/" .. file_path
        local dir = vim.fn.fnamemodify(full_path, ":h")
        vim.fn.mkdir(dir, "p")

        if not vim.endswith(file_path, "/") then
            local file = io.open(full_path, "w")
            if file then
                file:write("-- test content for " .. file_path .. "\n")
                file:close()
            end
        end
    end

    return temp_dir
end

-- Creates a custom project structure from a table definition
-- Args:
--   structure (table) - list of file paths to create
--   root_marker (string) - root marker file/dir to create (default: ".git/HEAD")
-- Returns: temp_dir (string) - path to temporary directory
function M.create_custom_project(structure, root_marker)
    root_marker = root_marker or ".git/HEAD"
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")

    -- Always create root marker first
    local marker_path = temp_dir .. "/" .. root_marker
    local marker_dir = vim.fn.fnamemodify(marker_path, ":h")
    vim.fn.mkdir(marker_dir, "p")

    if not vim.endswith(root_marker, "/") then
        local file = io.open(marker_path, "w")
        if file then
            file:write("root marker\n")
            file:close()
        end
    end

    -- Create custom structure
    for _, file_path in ipairs(structure) do
        local full_path = temp_dir .. "/" .. file_path
        local dir = vim.fn.fnamemodify(full_path, ":h")
        vim.fn.mkdir(dir, "p")

        if not vim.endswith(file_path, "/") then
            local file = io.open(full_path, "w")
            if file then
                file:write("-- test content for " .. file_path .. "\n")
                file:close()
            end
        end
    end

    return temp_dir
end

-- Creates a .filefliprc file in the given directory
-- Args:
--   dir (string) - directory to create .filefliprc in
--   content (string) - content of the RC file
function M.create_rc_file(dir, content)
    local rc_path = dir .. "/.filefliprc"
    local file = io.open(rc_path, "w")
    if file then
        file:write(content)
        file:close()
    end
    return rc_path
end

-- Cleanup temporary directory
-- Args:
--   temp_dir (string) - path to temporary directory to delete
function M.cleanup(temp_dir)
    if temp_dir and temp_dir ~= "" and vim.fn.isdirectory(temp_dir) == 1 then
        vim.fn.delete(temp_dir, "rf")
    end
end

-- Helper to get a file path within a temp directory
-- Args:
--   temp_dir (string) - base temp directory
--   relative_path (string) - relative path within temp dir
-- Returns: string - full path
function M.get_path(temp_dir, relative_path)
    return temp_dir .. "/" .. relative_path
end

return M
