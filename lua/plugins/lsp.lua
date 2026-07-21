return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = {
          spacing = 4,
          source = "if_many",
          format = function(d)
            return d.message
          end,
          severity_sort = true,
        },
        signs = true,
        underline = true,
        update_in_insert = true,
        float = { border = "rounded" },
      },
    },
  },
}
