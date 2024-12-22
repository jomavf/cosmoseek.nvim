local M = {}

local Job = require("plenary.job")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

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
						snippet_html = h.content and h.content.snippet or nil,
					},
				})
			end

			vim.schedule(function()
				M.open_picker(qf_items)
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

function M.open_picker(items)
	-- local results = {}
	-- for _, item in ipairs(items) do
	-- 	table.insert(results, item.text)
	-- end
	local results = items

	pickers
		.new({}, {
			prompt_title = "CosmoSeek",
			finder = finders.new_table({
				results = results,
				-- entry is one of our items
				entry_maker = function(entry)
					return {
						value = entry,
						display = string.format("%s/%s", entry.user_data.repo, entry.user_data.path),
						ordinal = entry.user_data.repo .. entry.user_data.path,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry)
					local item = entry.value
					local bufnr = self.state.bufnr

					-- OPTION A: Show the snippet from grep.app in the preview
					-- (This snippet is HTML, so it won't look super pretty unless I parse it.)
					-- We'll do a quick/naive parse to strip HTML tags:
					local snippet_html = item.user_data.snippet_html or ""
					local snippet_str = snippet_html
						:gsub("<[^>]*>", "") -- remove all HTML tags
						:gsub("&nbsp;", " ") -- decode some HTML entities
						:gsub("&amp;", "&")
						:gsub("&gt;", ">")
						:gsub("&lt;", "<")
					-- Clear the buffer and set lines
					vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
					local lines = {}
					for line in snippet_str:gmatch("([^\n]+)") do
						table.insert(lines, line)
					end
					if #lines == 0 then
						lines = { "[No snippet provided]" }
					end
					vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

					-- OPTION B: Alternatively, fetch the entire raw file from GitHub
					-- for preview.  But that can be slow if you have many results.
					-- See the "on_select" logic below for a demonstration of fetching
					-- the raw file for *opening* instead of for preview.
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				-- press enter <CR> to open the file in a new buffer (from github raw)
				local function on_select_file()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)

					if not selection or not selection.value then
						return
					end

					local item = selection.value
					M.open_file_from_github(item.user_data.repo, item.user_data.branch, item.user_data.path)
				end

				map("i", "<CR>", on_select_file)
				map("n", "<CR>", on_select_file)

				return true
			end,
		})
		:find()
end

function M.open_file_from_github(repo, branch, path)
	-- e.g. repo = "TanStack/query"
	local splitted = vim.split(repo, "/")
	if #splitted < 2 then
		vim.notify("Invalid repo: " .. repo)
		return
	end
	local owner = splitted[1]
	local repo_name = splitted[2]

	local raw_url =
		string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo_name, branch or "master", path)
	vim.notify("Fetching " .. raw_url)

	Job:new({
		command = "curl",
		args = { "-f", "-s", raw_url },
		on_exit = function(j, ret)
			if ret ~= 0 then
				vim.schedule(function()
					vim.notify("Failed to fetch " .. raw_url, vim.log.levels.ERROR)
				end)
				return
			end
			local lines = j:result()
			vim.schedule(function()
				-- Open in a new tab (or vsplit, etc.)
				vim.cmd("tabnew")
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_set_current_buf(buf)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.cmd("file " .. vim.fn.fnamemodify(path, ":t"))
			end)
		end,
	}):start()
end

return M
