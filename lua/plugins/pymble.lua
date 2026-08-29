return {
  {
    "alexpasmantier/pymple.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    build = ":PympleBuild",
    -- Pymple must be loaded before a file explorer can emit a rename event.
    lazy = false,
    opts = {
      update_imports = {
        enable = true,
      },
    },
    config = function(_, opts)
      require("pymple").setup(opts)

      -- Snacks Explorer calls Snacks.rename directly. Disable its LSP file
      -- operation pass and let Pymple perform the Python import update once.
      vim.schedule(function()
        if not (Snacks and Snacks.rename) then
          return
        end

        local rename = Snacks.rename
        if rename._pymple_original_rename_file then
          return
        end

        local original_rename_file = rename.rename_file

        rename.on_rename_file = function(_, _, callback)
          callback()
        end

        rename.rename_file = function(rename_opts)
          rename_opts = rename_opts or {}
          local user_callback = rename_opts.on_rename
          rename_opts.on_rename = function(to, from, ok)
            if user_callback then
              user_callback(to, from, ok)
            end
            if ok and (from:match("%.py$") or to:match("%.py$")) then
              vim.schedule(function()
                local config = require("pymple.config")
                require("pymple.api").update_imports(
                  from,
                  to,
                  config.user_config.update_imports
                )
              end)
            end
          end
          return original_rename_file(rename_opts)
        end

        -- Keep a reference so this wrapper is only installed once.
        rename._pymple_original_rename_file = original_rename_file
      end)
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local global = opts.servers and opts.servers["*"]
      if global and global.keys then
        global.keys = vim.tbl_filter(function(key)
          return key[1] ~= "<leader>cR"
        end, global.keys)
      end
    end,
  },
}
