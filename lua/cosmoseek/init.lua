local M = {}
local search = require("cosmoseek.search")

function M.setup(opts)
	opts = opts or {}
	M.options = {
		title = opts.title or "CosmoSeek",
		use_location_list = opts.use_location_list or false,
	}
end

function M.search(query)
	search.search_api(query)
end

return M
