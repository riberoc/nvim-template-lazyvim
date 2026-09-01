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
        update_in_insert = false,
        float = { border = "rounded" },
        severity_sort = true,
      },
      inlay_hints = {
        enabled = false,
      },
      servers = {
        basedpyright = { enabled = false },
        ty = {
          -- Keep Neovim's pull-diagnostics support enabled for Ty's workspace mode.
          capabilities = {
            textDocument = {
              diagnostic = {
                dynamicRegistration = false,
              },
            },
          },
          on_attach = function(client, bufnr)
            local group = vim.api.nvim_create_augroup("TyDiagnostics" .. bufnr, { clear = true })

            vim.api.nvim_create_autocmd("BufWritePost", {
              buffer = bufnr,
              group = group,
              callback = function()
                if client:is_stopped() or not client:supports_method("workspace/diagnostic") then
                  return
                end

                vim.defer_fn(function()
                  if not client:is_stopped() then
                    -- The request is workspace-scoped, but Ty incrementally
                    -- rechecks only the changed file and affected dependents.
                    vim.lsp.buf.workspace_diagnostics({ client_id = client.id })
                  end
                end, 100)
              end,
            })

            vim.defer_fn(function()
              if not client:is_stopped() and client:supports_method("workspace/diagnostic") then
                vim.lsp.buf.workspace_diagnostics({ client_id = client.id })
              end
            end, 500)
          end,
          settings = {
            ty = {
              diagnosticMode = "workspace",
            },
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
