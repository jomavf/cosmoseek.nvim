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
					user_data = {
						repo = h.repo.raw or "",
						branch = h.branch.raw or "master", -- o "main", depende de la respuesta
						path = h.path.raw or "",
					},
				})
			end

			-- Insertar en la Quickfix o Location list
			vim.schedule(function()
				-- Leer si usamos location list desde el 'setup'
				local opts = require("cosmoseek").options or {}
				local use_loclist = opts.use_location_list
				local title = opts.title or "CosmoSeek"

				if use_loclist then
					vim.fn.setloclist(0, {}, "r", {
						title = title,
						items = qf_items,
					})
					vim.cmd("lopen")
				else
					vim.fn.setqflist({}, "r", {
						title = title,
						items = qf_items,
					})
					vim.cmd("copen")
				end
			end)
		end,
	}):start()
end

function M.on_search_open()
	local qf_items = vim.fn.getqflist({ items = 1 }).items
	local qf_idx = vim.fn.getqflist({ idx = 0 }).idx
	if qf_idx == 0 or qf_items == nil then
		print("No hay resultados seleccionados.")
		return
	end

	local selected_item = qf_items[qf_idx]
	if not selected_item.user_data then
		print("No hay datos en user_data.")
		return
	end

	local repo = selected_item.user_data.repo
	local branch = selected_item.user_data.branch
	local path = selected_item.user_data.path

	-- (1) Parsear el "repo" que viene como "TanStack/query" => owner = "TanStack", repo_name = "query"
	local splitted = vim.split(repo, "/")
	if #splitted < 2 then
		print("No se pudo parsear el repositorio: " .. repo)
		return
	end
	local owner = splitted[1]
	local repo_name = splitted[2]

	-- (2) Construir la URL RAW de GitHub.
	--    Por ejemplo: "https://raw.githubusercontent.com/TanStack/query/main/scripts/publish.js"
	local raw_url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo_name, branch, path)

	print("Descargando: " .. raw_url)

	-- (3) Bajar el contenido y abrirlo en un buffer
	Job:new({
		command = "curl",
		args = { "-f", "-s", raw_url }, -- -f: fail early, -s: silencioso
		on_exit = function(job, return_val)
			if return_val ~= 0 then
				vim.schedule(function()
					print("No se pudo descargar el archivo. Verifica la URL.")
				end)
				return
			end

			local lines = job:result()
			-- Abrir buffer nuevo
			vim.schedule(function()
				vim.cmd("tabnew") -- por ejemplo, abrir en un tab nuevo
				local buf = vim.api.nvim_create_buf(false, true) -- Crear un buffer no listado
				vim.api.nvim_set_current_buf(buf)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.cmd("file " .. vim.fn.fnamemodify(path, ":t")) -- ponerle nombre al buffer (el nombre base del archivo)
				print("Archivo cargado en nuevo buffer.")
			end)
		end,
	}):start()
end

return M
