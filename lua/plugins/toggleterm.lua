return {
  "akinsho/toggleterm.nvim",
  version = "*",
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
      -- on_create = fun(t: Terminal),
      -- on_open = fun(t: Terminal),
      -- on_close = fun(t: Terminal),
      -- on_stdout = fun(t: Terminal, job: number, data: string[], name: string)
      -- on_stderr = fun(t: Terminal, job: number, data: string[], name: string)
      -- on_exit = fun(t: Terminal, job: number, exit_code: number, name: string)
      hide_numbers = true,
      -- shade_filetypes = {},
      -- autochdir = false,
      -- highlights = {
      --   Normal = { guibg = "<VALUE-HERE>" },
      --   NormalFloat = { link = 'Normal' },
      --   FloatBorder = { guifg = "<VALUE-HERE>", guibg = "<VALUE-HERE>" },
      -- },
      shade_terminals = true,
      -- shading_factor = '<number>',
      -- shading_ratio = '<number>',
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      persist_mode = true,
      direction = 'horizontal',
      close_on_exit = true,
      -- clear_env = false,
      shell = vim.o.shell,
      auto_scroll = true,
      float_opts = {
        border = 'curved',
        width = 120,
        height = 35,
        winblend = 3,
        -- row = <value>,
        -- col = <value>,
        -- zindex = <value>,
        -- title_pos = 'left' | 'center' | 'right',
      },
      -- winbar = {
      --   enabled = false,
      --   name_formatter = function(term) return term.name end,
      -- },
      -- responsiveness = {
      --   horizontal_breakpoint = 135,
      -- },
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

    vim.keymap.set("n", "<leader>wg", "<cmd>lua _lazygit_toggle()<CR>", { desc = "lazygit" })
    vim.keymap.set("n", "<leader>wt", "<cmd>ToggleTerm direction=horizontal<CR>", { desc = "terminal horizontal" })
    vim.keymap.set("n", "<leader>wT", "<cmd>ToggleTerm direction=vertical<CR>", { desc = "terminal vertical" })

    -- terminal navigation keymaps
    function _G.set_terminal_keymaps()
      local opts = { buffer = 0 }
      vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
      vim.keymap.set('t', 'jk', [[<C-\><C-n>]], opts)
      vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
      vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
      vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
      vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
      vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], opts)
    end

    vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')
  end,
}
