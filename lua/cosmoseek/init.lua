local M = {}
local search = require("cosmoseek.search")

function M.setup(opts)
	opts = opts or {}
	M.options = {}
end

function M.search(query)
	search.search_api(query)
end

function M.on_search_open()
	search.on_search_open()
end

return M
