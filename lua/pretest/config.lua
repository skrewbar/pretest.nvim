local M = {}

---@class pretest.Config
---@field save_dir string|nil
---@field ui "sidebar"|"float"
---@field sidebar_width integer
---@field float_width number
---@field float_height number
---@field default_time_limit integer
---@field default_memory_limit integer
---@field sidebar_sections { header: number, input: number, expected: number, output: number }
---@field float_sections { header: number, input: number, expected: number, output: number }
---@field languages table<string, pretest.LangConfig>

---@class pretest.RunCtx
---@field src_path string
---@field bin_path string

---@alias pretest.LangExec string|(fun(ctx: pretest.RunCtx): string)
---@alias pretest.LangArgs string[]|(fun(ctx: pretest.RunCtx): string[])

---@class pretest.CompileConfig
---@field exec pretest.LangExec
---@field args? pretest.LangArgs

---@class pretest.RunConfig
---@field exec pretest.LangExec
---@field args? pretest.LangArgs

---@class pretest.LangConfig
---@field compile? pretest.CompileConfig
---@field run pretest.RunConfig

local defaults = {
  save_dir = nil,
  ui = "sidebar",
  sidebar_width = 48,
  float_width = 0.4,
  float_height = 0.6,
  default_time_limit = 3000,
  default_memory_limit = 1024,
  sidebar_sections = {
    header = 1,
    input = 1,
    expected = 1,
    output = 1,
  },
  float_sections = {
    header = 1,
    input = 1,
    expected = 1,
    output = 1,
  },
  languages = {
    cpp = {
      compile = {
        exec = "g++",
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
