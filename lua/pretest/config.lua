local M = {}

---`(0, 1]` is a fraction of editor columns/lines; `> 1` is cells.
---@alias pretest.Size number

---@alias pretest.UiMode "n"|"i"
---@alias pretest.UiModes pretest.UiMode|pretest.UiMode[]

---One UI key. `[1]` is the Neovim lhs. Omit `modes` to use the action default.
---@class pretest.UiKey
---@field [1] string
---@field modes? pretest.UiModes

---@alias pretest.UiKeySpec
---| false
---| string
---| pretest.UiKey
---| (string|pretest.UiKey)[]

---@class pretest.UiKeyBinding
---@field lhs string
---@field modes string[]

---@class pretest.UiKeys
---@field next_case pretest.UiKeySpec
---@field prev_case pretest.UiKeySpec
---@field next_section pretest.UiKeySpec
---@field prev_section pretest.UiKeySpec
---@field close pretest.UiKeySpec
---@field stop pretest.UiKeySpec
---@field run_all pretest.UiKeySpec
---@field run_one pretest.UiKeySpec
---@field run_all_no_compile pretest.UiKeySpec
---@field run_one_no_compile pretest.UiKeySpec

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
---@field ui_keys pretest.UiKeys
---@field languages table<string, pretest.LangConfig>
---@field companion pretest.CompanionConfig

---@class pretest.CCTask
---@field name string
---@field group string
---@field url string
---@field interactive boolean?
---@field memoryLimit number
---@field timeLimit number
---@field tests { input: string, output: string }[]
---@field testType string?
---@field input table?
---@field output table?
---@field languages { java?: { mainClass?: string, taskClass?: string }, [string]: any }?
---@field batch { id: string, size: integer }?

---@alias pretest.CompanionPath string|(fun(task: pretest.CCTask, ext: string): string)

---@class pretest.CompanionConfig
---@field port integer
---@field listen_on_setup boolean
---@field extension string
---@field template string|table<string, string>|nil
---@field problem_path pretest.CompanionPath
---@field contest_dir pretest.CompanionPath
---@field contest_problem_path pretest.CompanionPath
---@field prompt_path boolean
---@field open boolean
---@field replace_testcases boolean

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
---@field extensions? string[] extra suffixes (no dot) mapped onto this filetype
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
  ui_keys = {
    next_case = "<C-n>",
    prev_case = "<C-p>",
    next_section = "<Tab>",
    prev_section = "<S-Tab>",
    close = "q",
    stop = "s",
    run_all = "R",
    run_one = "r",
    -- <C-R>/<C-r> are identical in terminals; use Ctrl-Shift-r for "all".
    run_all_no_compile = "<C-S-r>",
    run_one_no_compile = "<C-r>",
  },
  languages = {
    cpp = {
      extensions = { "cpp", "cc", "cxx", "c" },
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
      extensions = { "py" },
      run = {
        exec = "python3",
        args = function(ctx)
          return { ctx.src_path }
        end,
      },
    },
  },
  companion = {
    port = 27121,
    listen_on_setup = false,
    extension = "cpp",
    template = nil,
    problem_path = "{cwd}/{problem}.{ext}",
    contest_dir = "{cwd}",
    contest_problem_path = "{file}.{ext}",
    prompt_path = true,
    open = true,
    replace_testcases = true,
  },
}

---@type pretest.Config
M.options = vim.deepcopy(defaults)

local UI_KEY_MODES = {
  next_case = { "n", "i" },
  prev_case = { "n", "i" },
  next_section = { "n", "i" },
  prev_section = { "n", "i" },
  close = { "n" },
  stop = { "n" },
  run_all = { "n" },
  run_one = { "n" },
  run_all_no_compile = { "n" },
  run_one_no_compile = { "n" },
}

---@param modes pretest.UiModes|nil
---@param default string[]
---@return string[]
local function as_modes(modes, default)
  if type(modes) == "string" then
    return { modes }
  end
  if type(modes) == "table" then
    local out = {}
    for _, m in ipairs(modes) do
      if type(m) == "string" and m ~= "" then
        out[#out + 1] = m
      end
    end
    if #out > 0 then
      return out
    end
  end
  return vim.list_extend({}, default)
end

---@param item string|pretest.UiKey
---@param default_modes string[]
---@return pretest.UiKeyBinding|nil
local function binding_from(item, default_modes)
  if type(item) == "string" then
    if item == "" then
      return nil
    end
    return { lhs = item, modes = vim.list_extend({}, default_modes) }
  end
  if type(item) ~= "table" then
    return nil
  end
  local lhs = item[1]
  if type(lhs) ~= "string" or lhs == "" then
    return nil
  end
  return { lhs = lhs, modes = as_modes(item.modes, default_modes) }
end

---@param spec pretest.UiKeySpec|nil
---@param default_modes string[]
---@return pretest.UiKeyBinding[]
local function normalize_ui_key_spec(spec, default_modes)
  if spec == false or spec == nil then
    return {}
  end
  if type(spec) == "string" then
    local b = binding_from(spec, default_modes)
    return b and { b } or {}
  end
  if type(spec) ~= "table" then
    return {}
  end
  -- `{ "<Tab>", modes = "n" }` or `{ "<C-j>" }` is one binding; `{ "<Tab>", "<C-l>" }` is a list.
  local single = spec.modes ~= nil or (type(spec[1]) == "string" and spec[2] == nil)
  if single then
    local b = binding_from(spec, default_modes)
    return b and { b } or {}
  end
  local out = {}
  for _, item in ipairs(spec) do
    local b = binding_from(item, default_modes)
    if b then
      out[#out + 1] = b
    end
  end
  return out
end

---@param opts pretest.Config|nil
function M.setup(opts)
  opts = opts or {}
  local ui_keys = opts.ui_keys
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  -- Lists must replace per action; tbl_deep_extend would merge by index.
  if type(ui_keys) == "table" then
    M.options.ui_keys = vim.tbl_extend("force", vim.deepcopy(defaults.ui_keys), ui_keys)
  end
end

---@param action string
---@return pretest.UiKeyBinding[]
function M.ui_key_list(action)
  local default_modes = UI_KEY_MODES[action] or { "n" }
  local spec = (M.options.ui_keys or {})[action]
  return normalize_ui_key_spec(spec, default_modes)
end

---@param ft string|nil
---@return pretest.LangConfig|nil
function M.language(ft)
  if type(ft) ~= "string" then
    return nil
  end
  return M.options.languages[ft]
end

return M
