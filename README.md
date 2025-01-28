# Tests source for neo-tree

currently only provides tests discovered by [dotnet-bsp](https://github.com/616b2f/dotnet-bsp) server. But may be extendet later on.

# Installation

min supported neovim version is 0.10

## [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
      "616b2f/neo-tree-tests" -- <-- this plugin
    },
    config = function ()
      require("neo-tree").setup({
        sources = {
            "filesystem",
            "buffers",
            "git_status",
            "tests" -- <-- this plugin
        },
        tests = {
            -- The config for your source goes here. This is the same as any other source, plus whatever
            -- special config options you add.
            --window = {...}
            --renderers = { ..}
            --etc
        }
      })
    end
  },
```

# Credits

many thank to this plugins, I took them as insperation.

- https://github.com/nvim-neotest/neotest
- https://github.com/mrbjarksen/neo-tree-diagnostics.nvim
- https://github.com/prncss-xyz/neo-tree-zk.nvim
