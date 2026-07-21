return {
  "Davidyz/inlayhint-filler.nvim",
  keys = {
    {
      "<leader>ih",
      function()
        require("inlayhint-filler").fill()
      end,
      desc = "Fill inlay hint",
    },
  },
}
