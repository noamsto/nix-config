-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- disable diagnostics for .env files
local group = vim.api.nvim_create_augroup("__env", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = ".env*",
  group = group,
  callback = function(args)
    vim.diagnostic.enable(false, { bufnr = args.buf })
  end,
})

-- Set up custom filetypes
vim.filetype.add({
  filename = {
    [".*/*.test.hcl"] = "atlas-test",
    [".*/*.plan.hcl"] = "atlas-plan",
    [".*/*.rule.hcl"] = "atlas-rule",
  },
})

-- Tell Treesitter to treat Atlas filetypes as HCL for syntax highlighting
vim.treesitter.language.register('hcl', 'atlas-config')
vim.treesitter.language.register('hcl', 'atlas-schema-mysql')
vim.treesitter.language.register('hcl', 'atlas-schema-postgresql')
vim.treesitter.language.register('hcl', 'atlas-schema-sqlite')
vim.treesitter.language.register('hcl', 'atlas-schema-clickhouse')
vim.treesitter.language.register('hcl', 'atlas-schema-mssql')
vim.treesitter.language.register('hcl', 'atlas-schema-redshift')
vim.treesitter.language.register('hcl', 'atlas-test')
vim.treesitter.language.register('hcl', 'atlas-plan')
vim.treesitter.language.register('hcl', 'atlas-rule')

-- Set Jinja files to be highlighted as HTML
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = { "*.html.j2", "*.jinja", "*.jinja2", "*.j2" },
  command = "setlocal filetype=htmldjango",
})

-- Markdown buffer overrides: no wrap, no spell, no diagnostics.
-- Runs after LazyVim's `lazyvim_wrap_spell` FileType autocmd, so this wins.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    vim.opt_local.wrap = false
    vim.opt_local.spell = false
    vim.diagnostic.enable(false, { bufnr = args.buf })

    -- :MdSortTable — sort body rows of the markdown table under the cursor.
    -- Preserves the header row and the |---| separator row.
    -- Usage: :MdSortTable          (ascending, by column under cursor)
    --        :MdSortTable!         (descending)
    --        :MdSortTable 2        (sort by column 2)
    --        :MdSortTable! 3       (descending, column 3)
    vim.api.nvim_buf_create_user_command(args.buf, "MdSortTable", function(opts)
      local is_table_row = function(line)
        return line and line:match("^%s*|.*|%s*$") ~= nil
      end

      local cur_line = vim.api.nvim_win_get_cursor(0)[1]
      if not is_table_row(vim.fn.getline(cur_line)) then
        vim.notify("MdSortTable: cursor is not on a markdown table", vim.log.levels.WARN)
        return
      end

      local start_line = cur_line
      while start_line > 1 and is_table_row(vim.fn.getline(start_line - 1)) do
        start_line = start_line - 1
      end
      local end_line = cur_line
      local last = vim.api.nvim_buf_line_count(0)
      while end_line < last and is_table_row(vim.fn.getline(end_line + 1)) do
        end_line = end_line + 1
      end

      if end_line - start_line < 2 then
        vim.notify("MdSortTable: table has no body rows to sort", vim.log.levels.WARN)
        return
      end

      local sep_line = start_line + 1
      if not vim.fn.getline(sep_line):match("^%s*|[%s%-:|]+|%s*$") then
        vim.notify("MdSortTable: expected separator row at line " .. sep_line, vim.log.levels.WARN)
        return
      end

      -- Pick sort column: explicit arg, else cursor column, else 1.
      local col_idx
      if opts.args and opts.args ~= "" then
        col_idx = tonumber(opts.args)
      else
        local header = vim.fn.getline(start_line)
        local cur_col = vim.api.nvim_win_get_cursor(0)[2] + 1
        col_idx = 1
        local pipe = 0
        for i = 1, #header do
          if header:sub(i, i) == "|" then
            pipe = pipe + 1
            if i >= cur_col then
              col_idx = math.max(1, pipe - 1)
              break
            end
          end
        end
        if col_idx < 1 then col_idx = 1 end
      end

      local body_start = sep_line + 1
      local rows = vim.api.nvim_buf_get_lines(0, body_start - 1, end_line, false)
      local cell_of = function(row)
        local cells = {}
        for cell in row:gmatch("|([^|]*)") do
          table.insert(cells, vim.trim(cell))
        end
        return cells[col_idx] or ""
      end

      local desc = opts.bang
      table.sort(rows, function(a, b)
        local ca, cb = cell_of(a), cell_of(b)
        local na, nb = tonumber(ca), tonumber(cb)
        if na and nb then
          if desc then return na > nb else return na < nb end
        end
        if desc then return ca > cb else return ca < cb end
      end)
      vim.api.nvim_buf_set_lines(0, body_start - 1, end_line, false, rows)
    end, { bang = true, nargs = "?", desc = "Sort markdown table body rows" })
  end,
})
