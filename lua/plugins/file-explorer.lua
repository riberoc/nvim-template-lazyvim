return {
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" }, -- File icons
    keys = {
      { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Toggle Explorer" },
      { "<leader>o", "<cmd>NvimTreeFocus<cr>", desc = "Focus Explorer" },
    },
    opts = {
      -- Automatically sync tree focus with your current active buffer
      update_focused_file = {
        enable = true,
        update_root = false,
      },

      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.map.on_attach.default(bufnr)

        vim.keymap.set(
          "n",
          "h",
          api.node.navigate.parent_close,
          { buffer = bufnr, desc = "Close Folder" }
        )
        vim.keymap.set("n", "l", api.node.open.edit, { buffer = bufnr, desc = "Open" })

        vim.keymap.set("n", "R", api.fs.rename_full, { buffer = bufnr, desc = "Rename Full Path" })
      end,

      -- Visual and UI tweaks
      view = {
        width = 35,
        side = "left",
      },

      renderer = {
        group_empty = true, -- Compacts empty nested folders (e.g., foo/bar/baz)
        highlight_git = true, -- Highlights file names based on Git status
        icons = {
          show = {
            git = true,
            folder = true,
            file = true,
            folder_arrow = true,
          },
        },
      },

      -- Git integration options
      git = {
        enable = true,
        ignore = false, -- Shows .gitignore files (faded) instead of hiding them completely
        timeout = 400,
      },

      -- Smart filtering and hiding options
      filters = {
        dotfiles = false, -- Shows hidden files (starting with .)
        custom = { "^\\.git$", "__pycache__" },
      },

      -- Helpful diagnostic badges if using Neovim's built-in LSP
      diagnostics = {
        enable = true,
        show_on_dirs = true,
      },

      -- Quality of life system interactions
      actions = {
        open_file = {
          quit_on_open = false, -- Keeps tree open when a file is selected
          window_picker = {
            enable = true, -- Prompts which window split to open the file into
          },
        },
      },
    },
  },
}
