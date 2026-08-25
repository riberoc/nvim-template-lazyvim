return {
  -- install ruff binary
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      table.insert(opts.ensure_installed, "ruff")
    end,
  },

  -- use ruff/black/prettier to format python on save
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "ruff_organize_imports", "ruff_format", "black" },
        lua = { "stylua" },
      },
      formatters = {
        prettier = {
          prepend_args = { "--print-width", "80" },
        },
        black = {
          prepend_args = { "--line-length", "80" },
        },
        ruff_format = {
          prepend_args = { "--line-length", "80" },
        },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true, -- Falls back to LSP formatting if formatter isn't found
      },
    },
  },

  -- use ruff to lint python
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        python = { "ruff" },
      },
    },
  },
}
