# FileFlip

## Problem

You want to quickly flip between files that are clearly related but may be in different directories for a given project.
For example, `foo.h` and `foo.cpp` could be in `a/include/b/c/foo.h` and `a/src/c/foo.cpp` respectively -- they clearly
share a base filename `foo` and only differ in their extension and location in the directory tree.

## This Solution

Provide two ways to switch between related files using their base filename as the point of commonality:
- Use a file extension mapping (e.g. `foo.h` <-> `foo.cpp`).
- Use a prefix and/or suffix mapping, but assume the same extension (e.g. `foo.cpp` <-> `foo_test.cpp`).

There are certain additional desirable properties of a solution:
- It should be an exhaustive search of the project's directory structure for the similar file -- the search should start
    from the current file's directory, and eventually work its way back up (and down) the directory structure.
- Prevent searching for anything above a detected project root directory. The project root is determined intelligently
    by finding one of a set of special files or directories that should only exist at a project root (e.g. a `.git`
    directory).
- It should be fast, utilizing cached knowledge from previous searches to avoid doing the exhaustive search, which can
    be very slow. For example, after searching and finding the mapping for `foo.h` above, finding a similar mapping
    between `a/include/b/c/bar.h` and `a/src/c/bar.cpp` should not require a search.
- The plugin should be configurable both globally and per project.

## Installation

- Neovim required
- Install using your favorite plugin manager (e.g. [lazy.nvim](https://lazy.folke.io/usage)).
- Optionally configure your own global configuration settings with something similar to this:
```
{
   'samr/fileflip.nvim',
    config = function()
      require("fileflip").setup({
        -- Add your own extension mappings here, for example:
        extension_maps = {
            h = { "cpp", "cc", "c" },
            hpp = { "cpp", "cc" },
            c = { "h" },
            cc = { "hpp", "h" },
            cpp = { "hpp", "h" },
        },

        -- Add your own alternative mappings here, for example:
        prefix_suffix_maps = {
            ["test_/"] = { "" },      -- prefix  (test_foo.cc -> foo.cc)
            ["/_test"] = { "" },      -- suffix  (foo_test.cc -> foo.cc)
            ["test_/_spec"] = { "" }, -- prefix/suffix  (test_foo_spec.cc -> foo.cc)
            [""] = { "_test", "test_/", "test_/_spec" },  -- maps back (foo.cc -> *)
        },

        -- Set project root markers (i.e. files or directories that exist only in project root).
        root_markers = { ".git", "package.json" },

        -- Adjust cache size (i.e. number of files and directory mappings to store, default=10000)
        cache_size = 500,
    })
    end,
}
```

## Per-project Configuration

Creating a `.filefliprc` file in the project root directory allows overriding global configuration settings. The file
uses the same syntax as the lua configuration. An example of what the file might look like is as follows.

```
# This is a .filefliprc file
cache_size = 5000

extension_maps = {
    h = { "cpp", "cc", "c" },
    hpp = { "cpp", "cc" },
    c = { "h" },
    cc = { "hpp", "h" },
    cpp = { "hpp", "h" },
}

prefix_suffix_maps = {
    ["_test"] = { "" },  -- another way to represent a suffix
    ["test_/"] = { "" },
    ["test_/_spec"] = { "" },
    [""] = { "_test", "test_/", "test_/_spec" },
}
```

The `.filefliprc` file will be auto-loaded when changing buffers or creating new ones. The auto-loading can be turned
off with `autoload_filefliprc = false`, in which case it will only be loaded once on Neovim start based on the current
working directory. The loading of `.filefliprc` files can be turned off altogether by setting `ignore_filefliprc = true`.

## Default Commands

The default commands available are:

- `:FileFlipByExtension` - Switch to the first available related file based on extension mappings
- `:FileFlipByPrefixSuffix` - Switch to the first available related file based on prefix/suffix mappings
- `:FileFlipByExtensionShow` - List all available files for current basename based on extension mappings
- `:FileFlipByPrefixSuffixShow` - List all available files for current basename based on prefix/suffix mappings
- `:FileFlipClearCache` - Clear the cache
- `:FileFlipShowStats` - Show cache usage statistics
- `:FileFlipShowConfig` - Attempt to show the current configuration
- `:FileFlipLoadConfig` - Attempt to load or reload any .filefliprc config file found (will not exist when `ignore_filefliprc` is true)

To map them to keys you can use something like the following.

```
vim.keymap.set('n', '<leader>fs', '<cmd>FileFlipByExtension<cr>', { desc = 'Switch to related file using extension' })
vim.keymap.set('n', '<leader>fa', '<cmd>FileFlipByPrefixSuffix<cr>', { desc = 'Switch to related file using prefix/suffix' })
vim.keymap.set('n', '<leader>ffs', '<cmd>FileFlipByExtensionShow<cr>', { desc = 'Show available files by extension' })
vim.keymap.set('n', '<leader>ffa', '<cmd>FileFlipByPrefixSuffixShow<cr>', { desc = 'Show available files by prefix/suffix' })
```

However, these mappings are not provided by default.


## Default Configuration

The default global configuration settings are as follows:
```
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
        ["_test"] = { "" },       
        ["test_/"] = { "" },      
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
```

Note that if you override a specific default setting, it will entirely replace the value rather than doing a merge of
what was there. For example, when loading the above example `.filefliprc` file, it will replace the default
`extension_maps` value such that there is no mapping for going between "html" and "js" files. However, a merge is done
across all the settings such that, in that example, the `cache_size` will remain 10000, since it was not overridden or
specified explicitly.

## Thanks

The following plugins provide similar functionality and were an inspiration for this one:

- [tpope/vim-projectionist](https://github.com/tpope/vim-projectionist)
- [jakemason/ouroboros](https://github.com/jakemason/ouroboros.nvim)
