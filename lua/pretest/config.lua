local M = {}

---`(0, 1]` is a fraction of editor columns/lines; `> 1` is cells.
---@alias pretest.Size number

---@class pretest.Config
---@field save_dir string|nil
---@field ui "sidebar"|"float"
---@field sidebar_width pretest.Size
---@field sidebar_min_width pretest.Size|nil
---@field sidebar_max_width pretest.Size|nil
---@field float_width pretest.Size
---@field float_height pretest.Size
---@field float_min_width pretest.Size|nil
---@field float_max_width pretest.Size|nil
---@field float_min_height pretest.Size|nil
---@field float_max_height pretest.Size|nil
---@field default_time_limit integer
---@field default_memory_limit integer
---@field show_header_hints boolean
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
  sidebar_width = 40,
  sidebar_min_width = nil,
  sidebar_max_width = nil,
  float_width = 0.6,
  float_height = 0.8,
  float_min_width = 30,
  float_max_width = nil,
  float_min_height = 16,
  float_max_height = nil,
  default_time_limit = 3000,
  default_memory_limit = 1024,
  show_header_hints = true,
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
        args = { "-o", "$bin", "$src" },
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
