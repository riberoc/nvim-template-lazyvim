return {
  {
    "artemave/workspace-diagnostics.nvim",
    dependencies = { "neovim/nvim-lspconfig", "folke/which-key.nvim" },
    keys = {
      {
        "<leader>cu",
        function()
          local clients = vim.lsp.get_clients()
          for _, client in ipairs(clients) do
            -- Skip tools like Copilot that don't declare filetypes or don't generate diagnostics
            if client.config and client.config.filetypes then
              require("workspace-diagnostics").populate_workspace_diagnostics(client, 0)
            end
          end
        end,
        desc = "Update Workspace Diagnostics",
        mode = "n",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = {
          spacing = 4,
          source = "if_many",
          format = function(diagnostic)
            return diagnostic.message
          end,
        },
        signs = true,
        underline = true,
        update_in_insert = true, -- Live updates for active buffer while typing
        float = { border = "rounded" },
        severity_sort = true,
      },
      inlay_hints = {
        enabled = true,
      },
      servers = {
        -- 1. REMOVED the global capabilities override so Neovim's file watcher can function

        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                pythonVersion = "3.14",
                diagnosticMode = "workspace",
                typeCheckingMode = "recommended",
                reportUninitializedInstanceVariable = "warning",
                autoSearchPaths = true,
                autoImportCompletions = true,
                useLibraryCodeForTypes = true,
                inlayHints = {
                  variableTypes = true,
                  callArgumentNames = true,
                  functionReturnTypes = true,
                  genericTypes = true,
                },
              },
              python = {
                pythonPath = vim.fn.exepath("python3.14"),
              },
            },
            -- Note: I removed the duplicate `python = { analysis = ... }` block you had here.
            -- Basedpyright reads from the `basedpyright` table directly in Neovim.
          },
        },
        pyright = { enabled = false },
        pylsp = { enabled = false },
      },
    },
  },
  {
    "ray-x/lsp_signature.nvim",
    event = "InsertEnter",
    opts = {},
  },
}
