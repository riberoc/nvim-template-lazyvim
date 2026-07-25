return {
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
        update_in_insert = true,
        float = { border = "rounded" },
        severity_sort = true,
      },
      inlay_hints = {
        enabled = true,
      },
      servers = {
        ["*"] = {
          capabilities = {
            workspace = {
              didChangeWatchedFiles = {
                dynamicRegistration = true,
              },
            },
          },
        },
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                diagnosticMode = "workspace",
                typeCheckingMode = "recommended",
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
            },
          },
        },
        pyright = { enabled = false },
        pylsp = { enabled = false },
      },
    },
  },
}
