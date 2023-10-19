local function fmt_with_edit()
	local win_state = vim.call("winsaveview")

	vim.lsp.buf.format({ name = "efm" })

	vim.cmd("edit!")
	vim.call("winrestview", win_state)
end

local function efm_fmt(buf)
	local matched_clients = vim.lsp.get_active_clients({ name = "efm", bufnr = buf })

	if vim.tbl_isempty(matched_clients) then
		return
	end

	local efm = matched_clients[1]
	local ft = vim.api.nvim_buf_get_option(buf, "filetype")
	local formatters = efm.config.settings.languages[ft]

	local matches = vim.tbl_filter(function(fmt)
		return not fmt.formatStdin
	end, formatters)

	if not vim.tbl_isempty(matches) then
		fmt_with_edit()
	else
		vim.lsp.buf.format({ name = "efm" })
	end
end

return function(client, buffer)
	local clients_no_hover = { "ruff_lsp" }
	for _, no_hover_client_name in pairs(clients_no_hover) do
		if client.name == no_hover_client_name then
			client.server_capibilities.hoverProvider = false
		end
	end
end
