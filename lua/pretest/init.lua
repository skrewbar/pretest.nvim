local config = require("pretest.config")
local commands = require("pretest.commands")
local ui = require("pretest.ui")

local M = {}

---@param opts pretest.Config|nil
function M.setup(opts)
  config.setup(opts)
  commands.setup()
  ui.setup()
end

return M
