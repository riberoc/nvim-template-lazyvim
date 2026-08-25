return {
  {
    "artemave/workspace-diagnostics.nvim",
    dependencies = { "neovim/nvim-lspconfig" },
    opts = {},
    config = function()
      local workspace_versions = {}

      local function refresh_open_workspace_documents(client, current_buf)
        local root = client.config.root_dir
        if not root then
          return
        end

        local current_file = vim.api.nvim_buf_get_name(current_buf)
        local files = vim.fn.systemlist({ "git", "-C", root, "ls-files", "*.py" })

        for _, relative_path in ipairs(files) do
          local path = vim.fs.normalize(root .. "/" .. relative_path)
          if path ~= current_file and vim.fn.filereadable(path) == 1 then
            local uri = vim.uri_from_fname(path)
            workspace_versions[uri] = (workspace_versions[uri] or 0) + 1
            client:notify("textDocument/didChange", {
              textDocument = { uri = uri, version = workspace_versions[uri] },
              contentChanges = {
                { text = table.concat(vim.fn.readfile(path), "\n") },
              },
            })
          end
        end
      end

      -- Hook into Basedpyright when it attaches to any Python buffer
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.name == "basedpyright" then
            -- Populates diagnostics for all files in the background
            require("workspace-diagnostics").populate_workspace_diagnostics(client, args.buf)
          end
        end,
      })

      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.py",
        callback = function(args)
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = args.buf, name = "basedpyright" })) do
            refresh_open_workspace_documents(client, args.buf)
          end
        end,
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = {
          spacing = 4,
          source = "if_many",
          format = function(diagnostic)
            return diagnostic.message
          end,
        },
        signs = true,
        underline = true,
        update_in_insert = true, -- Live updates for active buffer while typing
        float = { border = "rounded" },
        severity_sort = true,
      },
      inlay_hints = {
        enabled = true,
      },
      servers = {
        -- 1. REMOVED the global capabilities override so Neovim's file watcher can function

        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                pythonVersion = "3.14",
                diagnosticMode = "workspace",
                typeCheckingMode = "recommended",
                reportUninitializedInstanceVariable = "warning",
                autoSearchPaths = true,
                autoImportCompletions = true,
                useLibraryCodeForTypes = true,
                inlayHints = {
                  variableTypes = true,
                  callArgumentNames = true,
                  functionReturnTypes = true,
                  genericTypes = true,
                },
              },
              python = {
                pythonPath = vim.fn.exepath("python3.14"),
              },
            },
            -- Note: I removed the duplicate `python = { analysis = ... }` block you had here.
            -- Basedpyright reads from the `basedpyright` table directly in Neovim.
          },
        },
        pyright = { enabled = false },
        pylsp = { enabled = false },
      },
    },
  },
  {
    "ray-x/lsp_signature.nvim",
    event = "InsertEnter",
    opts = {},
  },
}
