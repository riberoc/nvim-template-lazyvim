-- File: ~/.config/nvim/lua/plugins/python-hints.lua

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local hint_ns = vim.api.nvim_create_namespace("PythonInheritanceHints")
      local current_tick = 0

      ---------------------------------------------------------------------------
      -- TEMPLATE CONFIGURATION
      ---------------------------------------------------------------------------
      local TEMPLATE = [[
    {attr}: {type}
]]
      ---------------------------------------------------------------------------

      local function build_virt_lines(parent_name, attributes)
        local virt_lines = {}
        if #attributes == 0 then
          return virt_lines
        end

        for line in TEMPLATE:gmatch("[^\r\n]+") do
          if line:find("{attr}") then
            for _, item in ipairs(attributes) do
              local attr_type = (item.type and item.type ~= "") and item.type or "any"
              local formatted = line
                :gsub("{parent}", parent_name)
                :gsub("{attr}", item.name)
                :gsub("{type}", attr_type)
              table.insert(virt_lines, { { formatted, "Comment" } })
            end
          else
            local formatted = line:gsub("{parent}", parent_name)
            table.insert(virt_lines, { { formatted, "Comment" } })
          end
        end

        return virt_lines
      end

      -- Helper to extract raw text lines from target buffer to parse types if LSP detail fails
      local function get_line_text(target_bufnr, line_idx)
        local lines = vim.api.nvim_buf_get_lines(target_bufnr, line_idx, line_idx + 1, false)
        return lines[1] or ""
      end

      -- If the class at class_line has a docstring right below it, return the
      -- (0-indexed) line where that docstring closes, so hints render after
      -- it instead of shoving themselves between "class Foo:" and """doc""".
      -- If there is no docstring, just returns class_line unchanged.
      local function get_docstring_end_line(bufnr, class_line)
        local total_lines = vim.api.nvim_buf_line_count(bufnr)
        local scan_end = math.min(class_line + 50, total_lines)
        local lines = vim.api.nvim_buf_get_lines(bufnr, class_line + 1, scan_end, false)

        local i = 1
        while lines[i] and lines[i]:match("^%s*$") do
          i = i + 1
        end

        local first = lines[i]
        if not first then
          return class_line
        end

        local quote = first:match('^%s*(""")') or first:match("^%s*(''')")
        if not quote then
          return class_line
        end

        -- Single-line docstring: opening and closing triple-quote on same line.
        local rest = first:match('^%s*"""(.*)$') or first:match("^%s*'''(.*)$")
        if rest and rest:find(quote, 1, true) then
          return class_line + i
        end

        -- Multi-line docstring: scan forward for the closing triple-quote.
        for j = i + 1, #lines do
          if lines[j]:find(quote, 1, true) then
            return class_line + j
          end
        end

        -- Unterminated within scan window; fall back to the class line.
        return class_line
      end

      -- Recursively search a documentSymbol tree for a class matching parent_name.
      -- Fixes the old top-level-only "break" that missed nested classes.
      local function find_class_symbol(symbols, parent_name)
        for _, symbol in ipairs(symbols or {}) do
          if symbol.name == parent_name and symbol.kind == 5 then -- 5 = Class
            return symbol
          end
          local found = find_class_symbol(symbol.children, parent_name)
          if found then
            return found
          end
        end
        return nil
      end

      local function get_symbols_and_draw(target_bufnr, parent_name, child_line, bufnr, tick)
        local params = { textDocument = vim.lsp.util.make_text_document_params(target_bufnr) }

        vim.lsp.buf_request(
          target_bufnr,
          "textDocument/documentSymbol",
          params,
          function(err, result)
            if err or not result or tick ~= current_tick then
              return
            end
            if not vim.api.nvim_buf_is_valid(bufnr) then
              return
            end

            local attributes = {}
            local class_symbol = find_class_symbol(result, parent_name)

            if class_symbol then
              for _, child in ipairs(class_symbol.children or {}) do
                if not child.name:match("^__.+__$") then
                  -- 7=Property, 8=Field, 13=Variable, 14=Constant
                  if child.kind == 7 or child.kind == 8 or child.kind == 13 or child.kind == 14 then
                    local attr_type = ""

                    if child.detail and child.detail ~= "" then
                      attr_type = child.detail
                    end

                    if (not attr_type or attr_type == "") and child.range then
                      local line_text = get_line_text(target_bufnr, child.range.start.line)
                      -- vim.pesc escapes any Lua pattern magic characters in the name
                      local t = line_text:match("%s*" .. vim.pesc(child.name) .. "%s*:%s*([^=:#]+)")
                      if t then
                        attr_type = vim.trim(t)
                      end
                    end

                    table.insert(attributes, { name = child.name, type = attr_type })
                  end
                end
              end
            end

            if #attributes > 0 then
              local virt_lines = build_virt_lines(parent_name, attributes)
              -- Place hints after the class's own docstring, if it has one,
              -- instead of always right under "class Foo(Bar):".
              local draw_line = get_docstring_end_line(bufnr, child_line)
              vim.api.nvim_buf_set_extmark(bufnr, hint_ns, draw_line, 0, {
                virt_lines = virt_lines,
                virt_lines_above = false,
                priority = 50,
              })
            end
          end
        )
      end

      local function resolve_parent_and_draw(bufnr, parent_name, line_num, col, tick)
        local params = {
          textDocument = vim.lsp.util.make_text_document_params(bufnr),
          position = { line = line_num, character = col },
        }

        vim.lsp.buf_request(bufnr, "textDocument/definition", params, function(err, result)
          if err or not result or vim.tbl_isempty(result) or tick ~= current_tick then
            return
          end

          local location = result[1] or result
          local uri = location.uri or location.targetUri
          if not uri then
            return
          end

          local target_bufnr = vim.uri_to_bufnr(uri)
          if not vim.api.nvim_buf_is_loaded(target_bufnr) then
            vim.fn.bufload(target_bufnr)
          end

          get_symbols_and_draw(target_bufnr, parent_name, line_num, bufnr, tick)
        end)
      end

      local function update_inheritance_hints(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        current_tick = current_tick + 1
        local tick = current_tick
        vim.api.nvim_buf_clear_namespace(bufnr, hint_ns, 0, -1)

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        for i, line in ipairs(lines) do
          local child, parents_str = line:match("class%s+(%w+)%s*%((.-)%)")

          if child and parents_str then
            for parent in parents_str:gmatch("[%w_]+") do
              -- Whole-word match via Lua frontier pattern, so "Foo" no longer
              -- matches inside "FooBar".
              local col = line:find("%f[%w_]" .. parent .. "%f[^%w_]")
              if col then
                resolve_parent_and_draw(bufnr, parent, i - 1, col - 1, tick)
              end
            end
          end
        end
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("PythonInheritanceHintsAttach", { clear = true }),
        callback = function(args)
          local bufnr = args.buf
          if vim.bo[bufnr].filetype ~= "python" then
            return
          end

          vim.defer_fn(function()
            update_inheritance_hints(bufnr)
          end, 500)

          -- Guard against multiple LSP clients (e.g. pyright + ruff) attaching
          -- to the same buffer and stacking duplicate autocmds.
          if vim.b[bufnr].python_hints_autocmd_set then
            return
          end
          vim.b[bufnr].python_hints_autocmd_set = true

          vim.api.nvim_create_autocmd({ "InsertLeave", "BufWritePost" }, {
            buffer = bufnr,
            callback = function()
              update_inheritance_hints(bufnr)
            end,
          })
        end,
      })

      return opts
    end,
  },
}
