--- This is a test for Harper. I went house. vscode
return {
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
        update_in_insert = false,
        float = { border = "rounded" },
        severity_sort = true,
      },
      inlay_hints = {
        enabled = false,
      },
      servers = {
        harper_ls = {
          filetypes = {
            "gitcommit",
            "html",
            "markdown",
            "tex",
            "toml",
            "txt",
          },
          userDictPath = "~/.config/nvim/spell/",
          workspaceDictPath = "",
          fileDictPath = "",
          linters = {
            SpellCheck = true,
            SpelledNumbers = false,
            AnA = true,
            SentenceCapitalization = true,
            UnclosedQuotes = true,
            WrongApostrophe = false,
            LongSentences = true,
            RepeatedWords = true,
            Spaces = true,
            CorrectNumberSuffix = true,
          },
          codeActions = {
            ForceStable = false,
          },
          markdown = {
            IgnoreLinkTitle = false,
          },
          diagnosticSeverity = "hint",
          isolateEnglish = false,
          dialect = "American",
          maxFileLength = 120000,
          ignoredLintsPath = "",
          excludePatterns = {},
        },
        basedpyright = { enabled = false },
        ty = {
          capabilities = {
            textDocument = {
              diagnostic = {
                dynamicRegistration = true,
              },
            },
          },
          on_attach = function(client, bufnr)
            local group = vim.api.nvim_create_augroup("TyDiagnostics" .. bufnr, { clear = true })

            vim.api.nvim_create_autocmd("BufWritePost", {
              buffer = bufnr,
              group = group,
              callback = function()
                if client:is_stopped() or not client:supports_method("workspace/diagnostic") then
                  return
                end

                vim.defer_fn(function()
                  if not client:is_stopped() then
                    vim.lsp.buf.workspace_diagnostics({ client_id = client.id })
                  end
                end, 500)
              end,
            })
          end,
          settings = {
            ty = {
              diagnosticMode = "workspace",
            },
          },
        },
        pyright = { enabled = false },
        pylsp = { enabled = false },

        -- LTEX CONFIGURATION
        ltex = {
          filetypes = { "bib", "markdown", "org", "tex" },
          settings = {
            ltex = {
              language = "en-US",
              -- This forces LTeX to only compute diagnostics when the file is saved
              checkFrequency = "save",
            },
          },
        },
      },
    },
  },
  {
    "ray-x/lsp_signature.nvim",
    event = "InsertEnter",
    opts = {},
  },
}
