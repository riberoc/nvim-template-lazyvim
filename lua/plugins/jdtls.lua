return {
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
      local jdtls = require("jdtls")

      local root_dir = require("jdtls.setup").find_root({ ".git", "pom.xml", "build.gradle", "Makefile" })
        or vim.fn.getcwd()

      -- load project-local overrides from .nvim.lua if present
      local project_cfg = {}
      local nvim_lua = root_dir .. "/.nvim.lua"
      if vim.fn.filereadable(nvim_lua) == 1 then
        local ok, cfg = pcall(dofile, nvim_lua)
        if ok and type(cfg) == "table" and cfg.jdtls then
          project_cfg = cfg.jdtls
        end
      end

      local workspace = vim.fn.expand("~/.cache/jdtls/workspace/")
        .. vim.fn.fnamemodify(root_dir, ":t")

      jdtls.start_or_attach({
        cmd = {
          vim.fn.exepath("jdtls"),
          "-data", workspace,
        },
        root_dir = root_dir,
        settings = {
          java = {
            project = {
              referencedLibraries = project_cfg.libs or {},
              sourcePaths = project_cfg.sourcePaths or {},
            },
          },
        },
        init_options = {
          bundles = {},
        },
      })
    end,
  },
}
