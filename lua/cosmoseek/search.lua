local Job = require("plenary.job")
local M = {}

function M.search_api(query)
	if not query or query == "" then
		vim.notify("CosmoSeek: no se ha proporcionado ningún texto de búsqueda", vim.log.levels.WARN)
		return
	end

	Job:new({
		command = "curl",
		args = {
			"-s",
			"https://grep.app/api/search?q=" .. query,
		},
		on_exit = function(j, return_val)
			if return_val ~= 0 then
				vim.schedule(function()
					vim.notify("Error realizando la búsqueda", vim.log.levels.ERROR)
				end)
				return
			end

			local result = table.concat(j:result(), "\n")
			local decoded = vim.json.decode(result)

			local hits = decoded.hits and decoded.hits.hits or {}
			if #hits == 0 then
				vim.schedule(function()
					vim.notify("CosmoSeek: No se encontraron resultados para '" .. query .. "'")
				end)
				return
			end

			-- Construimos la lista
			local qf_items = {}
			for _, h in ipairs(hits) do
				table.insert(qf_items, {
					filename = h.path.raw or "",
					lnum = 1,
					text = string.format("Repo: %s | Path: %s", h.repo.raw or "?", h.path.raw or "??"),
				})
			end

			-- Insertar en la Quickfix o Location list
			vim.schedule(function()
				-- Leer si usamos location list desde el 'setup'
				local opts = require("cosmoseek").options or {}
				local use_loclist = opts.use_location_list

				if use_loclist then
					vim.fn.setloclist(0, {}, "r", {
						title = "CosmoSeek results",
						items = qf_items,
					})
					vim.cmd("lopen")
				else
					vim.fn.setqflist({}, "r", {
						title = "CosmoSeek results",
						items = qf_items,
					})
					vim.cmd("copen")
				end
			end)
		end,
	}):start()
end

return M
