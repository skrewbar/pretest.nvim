local util = require("pretest.util")

local M = {}

---@class pretest.Config
---@field save_dir string
---@field ui "sidebar"|"float"
---@field sidebar_width integer
---@field float_width number
---@field float_height number
---@field default_time_limit integer
---@field default_memory_limit integer
---@field languages table<string, pretest.LangConfig>

---@class pretest.LangConfig
---@field compile? { exec: string|fun(): string, args: string[] }
---@field run { exec: string|fun(ctx: pretest.RunCtx): string, args?: string[]|fun(ctx: pretest.RunCtx): string[] }
---@field skip_compile? boolean

---@class pretest.RunCtx
---@field src_path string
---@field bin_path string

local defaults = {
  save_dir = vim.fn.expand("~/Programming/.cphbin"),
  ui = "sidebar",
  sidebar_width = 48,
  float_width = 0.38,
  float_height = 0.62,
  default_time_limit = 3000,
  default_memory_limit = 1024,
  languages = {
    cpp = {
      compile = {
        exec = util.default_cpp_compiler,
        args = { "-std=gnu++23", "-Wall", "-O2", "-o", "$bin", "$src" },
      },
      run = {
        exec = function(ctx)
          return ctx.bin_path
        end,
        args = {},
      },
    },
    python = {
      skip_compile = true,
      run = {
        exec = "python3",
        args = function(ctx)
          return { ctx.src_path }
        end,
      },
    },
  },
}

---@type pretest.Config
M.options = vim.deepcopy(defaults)

---@param opts pretest.Config|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@return pretest.Config
function M.get()
  return M.options
end

return M
