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
        update_in_insert = true, -- Live updates for active buffer while typing
        float = { border = "rounded" },
        severity_sort = true,
      },
      inlay_hints = {
        enabled = true,
      },
      servers = {
        basedpyright = { enabled = false },
        ty = {
          on_attach = function(client, bufnr)
            vim.defer_fn(function()
              if not client:is_stopped() then
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
