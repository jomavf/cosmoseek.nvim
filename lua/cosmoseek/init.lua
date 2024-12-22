local M = {}
local search = require("cosmoseek.search")

function M.setup(opts)
	opts = opts or {}
	M.options = {}

	vim.api.nvim_create_user_command("CosmoSeek", function(cmd_opts)
		search.search_api(cmd_opts.args)
	end, { nargs = 1, desc = "Busca en la API de grep.app y muestra resultados en la quickfix (o loclist)" })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "qf",
		callback = function()
			local qfinfo = vim.fn.getqflist({ title = true })
			if qfinfo.title == "CosmoSeek" then
				vim.keymap.set(
					"n",
					"<CR>",
					require("cosmoseek.search").on_search_open,
					{ buffer = true, desc = "Ejecuta open_selected_qf" }
				)
			end
		end,
	})
end

function M.search(query)
	search.search_api(query)
end

function M.on_search_open()
	search.on_search_open()
end

return M
