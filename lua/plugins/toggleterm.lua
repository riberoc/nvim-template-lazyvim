return {
  "akinsho/toggleterm.nvim",
  version = "*",
  -- Register keymaps directly with lazy.nvim so they work anytime (even on dashboard/empty buffers)
  keys = {
    { "<C-\\>", desc = "Toggle Terminal" },
    { "<leader>wT", "<cmd>ToggleTerm direction=horizontal<CR>", desc = "terminal horizontal" },
    { "<leader>wt", "<cmd>ToggleTerm direction=vertical<CR>", desc = "terminal vertical" },
    { "<leader>gg", "<cmd>lua _lazygit_toggle()<CR>", desc = "Lazygit" },
  },
  config = function()
    require("toggleterm").setup({
      size = function(term)
        if term.direction == "horizontal" then
          return 15
        elseif term.direction == "vertical" then
          return math.floor(vim.o.columns * 0.4)
        end
        return 20
      end,
      open_mapping = [[<c-\>]],
      hide_numbers = true,
      shade_terminals = true,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      persist_mode = true,
      direction = "horizontal",
      close_on_exit = true,
      shell = vim.o.shell,
      auto_scroll = true,
      float_opts = {
        border = "curved",
        width = 120,
        height = 35,
        winblend = 3,
      },
    })

    -- lazygit floating window
    local lazygit = require("toggleterm.terminal").Terminal:new({
      cmd = "lazygit",
      direction = "float",
      hidden = true,
    })

    function _G._lazygit_toggle()
      lazygit:toggle()
    end

    -- terminal navigation keymaps
    function _G.set_terminal_keymaps()
      local opts = { buffer = 0 }
      vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
      vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
      vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], opts)
      vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], opts)
      vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], opts)
      vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], opts)
      vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], opts)
    end

    vim.cmd("autocmd! TermOpen term://* lua set_terminal_keymaps()")
  end,
}
