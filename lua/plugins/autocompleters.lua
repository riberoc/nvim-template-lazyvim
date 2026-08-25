return {
  "L3MON4D3/LuaSnip",
  -- follow latest release.
  version = "v2.*",
  -- install jsregexp (optional!).
  build = "make install_jsregexp",
  dependencies = {
    "rafamadriz/friendly-snippets", -- Collection of common snippets
  },
  config = function()
    -- Load friendly-snippets + your own custom vscode snippets
    require("luasnip.loaders.from_vscode").lazy_load({
      paths = { vim.fn.stdpath("config") .. "/snippets" },
    })
  end,
}
