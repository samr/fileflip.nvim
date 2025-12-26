-- File system abstraction layer for fileflip.nvim
-- This module wraps all file system operations to enable testing

local M = {}

-- Default implementation using vim.fn
M.real = {
    filereadable = function(self, path)
        return vim.fn.filereadable(path) == 1
    end,

    isdirectory = function(self, path)
        return vim.fn.isdirectory(path) == 1
    end,

    fnamemodify = function(self, path, mods)
        return vim.fn.fnamemodify(path, mods)
    end,

    globpath = function(self, path, pattern, nosuf, list)
        return vim.fn.globpath(path, pattern, nosuf, list)
    end,

    tempname = function(self)
        return vim.fn.tempname()
    end,

    mkdir = function(self, path, flags)
        return vim.fn.mkdir(path, flags)
    end,
}

-- Mock implementation for testing
M.mock = {
    -- Virtual file system: { [path] = { type = "file"|"dir", content = "..." } }
    _fs = {},

    -- Reset the mock file system
    reset = function(self)
        self._fs = {}
    end,

    -- Add a file to the mock file system
    add_file = function(self, path, content)
        self._fs[path] = { type = "file", content = content or "" }
        -- Also add parent directories
        local dir = vim.fn.fnamemodify(path, ":h")
        while dir ~= "/" and dir ~= "." and dir ~= path do
            if not self._fs[dir] then
                self._fs[dir] = { type = "dir" }
            end
            local parent = vim.fn.fnamemodify(dir, ":h")
            if parent == dir then break end
            dir = parent
        end
    end,

    -- Add a directory to the mock file system
    add_directory = function(self, path)
        self._fs[path] = { type = "dir" }
        -- Also add parent directories
        local dir = vim.fn.fnamemodify(path, ":h")
        while dir ~= "/" and dir ~= "." and dir ~= path do
            if not self._fs[dir] then
                self._fs[dir] = { type = "dir" }
            end
            local parent = vim.fn.fnamemodify(dir, ":h")
            if parent == dir then break end
            dir = parent
        end
    end,

    filereadable = function(self, path)
        local entry = self._fs[path]
        return entry ~= nil and entry.type == "file"
    end,

    isdirectory = function(self, path)
        local entry = self._fs[path]
        return entry ~= nil and entry.type == "dir"
    end,

    fnamemodify = function(self, path, mods)
        -- Just delegate to real vim.fn for path manipulation
        return vim.fn.fnamemodify(path, mods)
    end,

    globpath = function(self, path, pattern, nosuf, list)
        -- Simple glob implementation for testing
        -- Convert pattern like "**/*.h" to regex
        local results = {}

        -- Normalize the search pattern
        local search_pattern = pattern:gsub("%*%*/", ""):gsub("^%*%*", "")
        local basename_pattern = search_pattern:match("([^/]+)$")

        if basename_pattern then
            for file_path, entry in pairs(self._fs) do
                if entry.type == "file" and vim.startswith(file_path, path) then
                    local basename = vim.fn.fnamemodify(file_path, ":t")
                    -- Simple pattern matching - just check if basename matches
                    local pattern_regex = basename_pattern:gsub("%.", "%%."):gsub("%*", ".*")
                    if basename:match("^" .. pattern_regex .. "$") then
                        table.insert(results, file_path)
                    end
                end
            end
        end

        return list and results or table.concat(results, "\n")
    end,

    tempname = function(self)
        -- Generate a fake temp name
        return "/tmp/mock_" .. math.random(100000, 999999)
    end,

    mkdir = function(self, path, flags)
        self:add_directory(path)
        return 0
    end,
}

-- Current active file system (defaults to real)
M.current = M.real

-- Switch to mock file system (for testing)
function M.use_mock()
    M.current = M.mock
    M.mock:reset()
    return M.mock
end

-- Switch back to real file system
function M.use_real()
    M.current = M.real
end

-- Convenience wrappers that use M.current
function M.filereadable(path)
    return M.current.filereadable(M.current, path)
end

function M.isdirectory(path)
    return M.current.isdirectory(M.current, path)
end

function M.fnamemodify(path, mods)
    return M.current.fnamemodify(M.current, path, mods)
end

function M.globpath(path, pattern, nosuf, list)
    return M.current.globpath(M.current, path, pattern, nosuf, list)
end

function M.tempname()
    return M.current.tempname(M.current)
end

function M.mkdir(path, flags)
    return M.current.mkdir(M.current, path, flags)
end

return M
