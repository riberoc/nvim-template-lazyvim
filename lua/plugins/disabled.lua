return {
  { "markdownlint", enabled = false },

  --
  --
  {
    -- 1. Disable mini.animate completely (if enabled via LazyVim UI extras)
    { "echasnovski/mini.animate", enabled = false },

    -- 2. Disable animation on indent line guides

    -- 3. Disable fade/slide animation stages on popups/notifications
    -- 4. Disable cursor smear/trail plugins (if enabled via extras)
    { "sphamba/smear-cursor.nvim", enabled = false },
    { "karb94/neoscroll.nvim", enabled = false },
  },
}
