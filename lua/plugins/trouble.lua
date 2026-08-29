return {
  "folke/trouble.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    modes = {
      diagnostics = {
        filter = function(items)
          local root
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
            if client.config and client.config.root_dir then
              root = vim.fs.normalize(client.config.root_dir)
              break
            end
          end

          root = root or vim.fs.normalize(vim.fn.getcwd())
          local prefix = root .. "/"

          return vim.tbl_filter(function(item)
            local filename = item.filename and vim.fs.normalize(item.filename) or ""
            if filename:sub(1, #prefix) ~= prefix then
              return false
            end

            local relative = filename:sub(#prefix + 1)
            for component in relative:gmatch("[^/]+") do
              if component:sub(1, 1) == "." then
                return false
              end
            end

            return true
          end, items)
        end,
        win = {
          type = "split",
          position = "right",
          size = 0.3, -- takes 30% of the screen width
        },
      },
    },
  },
  keys = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
      desc = "Buffer Diagnostics (Trouble)",
    },
    {
      "<leader>xX",
      "<cmd>Trouble diagnostics toggle<cr>",
      desc = "Workspace Diagnostics (Trouble)",
    },
  },
}
