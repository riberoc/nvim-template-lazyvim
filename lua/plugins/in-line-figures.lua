-- fig:~/projects/kaggle/ai-agent-sec/docs/multirainbow.png
return {
  "riberoc/nvim-in-line-figures",
  url = "git@github.com:riberoc/nvim-in-line-figures.git",
  event = "VeryLazy",
  dependencies = { "3rd/image.nvim" },
  main = "in-line-figures",
  opts = {
    enable_workspace_lookup = true,
    default_image_dir = "docs",
    workspace_dirs = { vim.fn.getcwd() },
    debug = true,
  },
}
