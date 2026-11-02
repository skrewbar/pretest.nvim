local config = require("pretest.config")
local util = require("pretest.util")

local M = {}

---@class pretest.TestCase
---@field id number
---@field input string
---@field output string

---@class pretest.Problem
---@field name string
---@field url string
---@field tests pretest.TestCase[]
---@field interactive boolean
---@field memoryLimit integer
---@field timeLimit integer
---@field srcPath string
---@field group string

---@param src_path string
---@return string|nil
function M.prob_path(src_path)
  src_path = util.abspath(src_path)
  -- CPH-compatible: basename includes extension (e.g. .main.cpp_<md5>.prob).
  local base = vim.fn.fnamemodify(src_path, ":t")
  local dir = util.artifact_dir(src_path)
  local hash = util.md5(src_path)
  if not hash then
    util.notify("failed to compute md5 for srcPath", vim.log.levels.ERROR)
    return nil
  end
  return vim.fs.joinpath(dir, string.format(".%s_%s.prob", base, hash))
end

-- Largest integer a double (and JavaScript) represents exactly.
local MAX_ID = 2 ^ 53 - 1

---@param id any
---@return boolean
local function is_valid_id(id)
  return type(id) == "number" and id == math.floor(id) and id >= 1 and id <= MAX_ID
end

---Return a function yielding ids unused in `tests`: one above the largest valid
---id, or the smallest free positive integer once that would pass `MAX_ID`.
---@param tests pretest.TestCase[]
---@return fun(): integer
local function id_allocator(tests)
  local used, max_id = {}, 0
  for _, tc in ipairs(tests) do
    if is_valid_id(tc.id) then
      used[tc.id] = true
      max_id = math.max(max_id, tc.id)
    end
  end

  local free = 1
  return function()
    local id

    if max_id < MAX_ID then
      max_id = max_id + 1
      id = max_id
    else
      while used[free] do
        free = free + 1
      end
      id = free
    end
    used[id] = true

    return id
  end
end

---@param src_path string
---@return pretest.Problem
function M.new_local(src_path)
  src_path = util.abspath(src_path)
  local stem = vim.fn.fnamemodify(src_path, ":t:r")
  local cfg = config.options
  return {
    name = "Local: " .. stem,
    url = src_path,
    tests = {},
    interactive = false,
    memoryLimit = cfg.default_memory_limit,
    timeLimit = cfg.default_time_limit,
    srcPath = src_path,
    group = "local",
    ["local"] = true,
  }
end

---@param src_path string
---@return pretest.Problem, string|nil # problem, path
function M.load_or_create(src_path)
  src_path = util.abspath(src_path)
  local path = M.prob_path(src_path)
  if not path then
    return M.new_local(src_path), nil
  end

  local content = util.read_file(path)
  if not content then
    return M.new_local(src_path), path
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    util.notify("invalid .prob JSON, creating new local problem", vim.log.levels.WARN)
    return M.new_local(src_path), path
  end

  data.tests = data.tests or {}
  data.srcPath = data.srcPath or src_path
  data.timeLimit = data.timeLimit or config.options.default_time_limit
  data.memoryLimit = (data.memoryLimit == nil) and config.options.default_memory_limit or data.memoryLimit
  data.name = data.name or ("Local: " .. vim.fn.fnamemodify(src_path, ":t:r"))
  data.url = data.url or src_path
  data.group = data.group or "local"
  if data.interactive == nil then
    data.interactive = false
  end
  if data["local"] == nil then
    data["local"] = true
  end

  -- Keep the first of each valid id; renumber repeats and missing/invalid ids.
  local seen, renumber = {}, {}
  for _, tc in ipairs(data.tests) do
    tc.input = util.ensure_string(tc.input)
    tc.output = util.ensure_string(tc.output)

    if is_valid_id(tc.id) and not seen[tc.id] then
      seen[tc.id] = true
    else
      renumber[#renumber + 1] = tc
    end
  end

  local next_id = id_allocator(data.tests)
  for _, tc in ipairs(renumber) do
    tc.id = next_id()
  end

  return data --[[@as pretest.Problem]], path
end

---Move a `.prob` to the name implied by `new_src`. Updates `srcPath` (and
---`url` / local `name` when they still match the old path). `problem` is
---mutated when provided; otherwise the old file is loaded from disk.
---@param old_src string
---@param new_src string
---@param problem pretest.Problem|nil
---@return pretest.Problem|nil
---@return string|nil new_path
---@return string|nil err
function M.relocate(old_src, new_src, problem)
  old_src = util.abspath(old_src)
  new_src = util.abspath(new_src)
  local old_path = M.prob_path(old_src)
  local new_path = M.prob_path(new_src)
  if not new_path then
    return nil, nil, "failed to compute new .prob path"
  end

  if old_path ~= new_path and vim.fn.filereadable(new_path) == 1 then
    return nil, new_path, "destination .prob already exists: " .. new_path
  end

  if not problem then
    if old_path then
      local content = util.read_file(old_path)
      if content then
        local ok, data = pcall(vim.json.decode, content)
        if ok and type(data) == "table" then
          problem = data --[[@as pretest.Problem]]
        end
      end
    end
  end

  if not problem then
    return nil, new_path, nil
  end

  local old_stem = vim.fn.fnamemodify(old_src, ":t:r")
  local new_stem = vim.fn.fnamemodify(new_src, ":t:r")
  if problem.name == "Local: " .. old_stem then
    problem.name = "Local: " .. new_stem
  end
  if problem.url == old_src then
    problem.url = new_src
  end
  problem.srcPath = new_src

  if not M.save(problem, new_path) then
    return problem, new_path, "failed to write .prob: " .. new_path
  end

  if old_path and old_path ~= new_path and vim.fn.filereadable(old_path) == 1 then
    vim.fn.delete(old_path)
  end

  return problem, new_path, nil
end

---@param problem pretest.Problem
---@param path string|nil
---@return boolean
function M.save(problem, path)
  path = path or M.prob_path(problem.srcPath)
  if not path then
    return false
  end
  local ok, err = util.write_file(path, vim.json.encode(problem))
  if not ok then
    util.notify("failed to write .prob: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

---@param tests { input: string, output: string }[]|nil
---@return pretest.TestCase[]
local function tests_from_companion(tests)
  local out = {}
  local next_id = id_allocator(out)
  for i, tc in ipairs(tests or {}) do
    out[i] = {
      id = next_id(),
      input = util.ensure_string(tc.input),
      output = util.ensure_string(tc.output),
    }
  end
  return out
end

---Convert a Competitive Companion task into a `.prob` table, preserving extra fields.
---@param task pretest.CCTask|table
---@param src_path string
---@return pretest.Problem
function M.from_companion(task, src_path)
  src_path = util.abspath(src_path)
  local cfg = config.options
  local problem = vim.deepcopy(task)
  if type(problem) ~= "table" then
    problem = {}
  end
  problem.srcPath = src_path
  problem["local"] = false
  problem.name = problem.name or ("Local: " .. vim.fn.fnamemodify(src_path, ":t:r"))
  problem.url = problem.url or src_path
  problem.group = problem.group or "local"
  if problem.interactive == nil then
    problem.interactive = false
  end
  problem.memoryLimit = (problem.memoryLimit == nil) and cfg.default_memory_limit or problem.memoryLimit
  problem.timeLimit = problem.timeLimit or cfg.default_time_limit
  problem.tests = tests_from_companion(task.tests)
  return problem --[[@as pretest.Problem]]
end

---@param problem pretest.Problem
---@return pretest.TestCase
function M.add_testcase(problem)
  local tc = {
    id = id_allocator(problem.tests)(),
    input = "",
    output = "",
  }
  table.insert(problem.tests, tc)
  return tc
end

---Insert copies of `cases` starting at `pos` (1-based) with ids unused in `problem`.
---@param problem pretest.Problem
---@param pos integer
---@param cases { input: string, output: string }[]
function M.insert_testcases(problem, pos, cases)
  local next_id = id_allocator(problem.tests)
  for i, tc in ipairs(cases) do
    table.insert(problem.tests, pos + i - 1, {
      id = next_id(),
      input = util.ensure_string(tc.input),
      output = util.ensure_string(tc.output),
    })
  end
end

---@param problem pretest.Problem
---@param index integer 1-based
---@return boolean
function M.delete_testcase(problem, index)
  if index < 1 or index > #problem.tests then
    return false
  end
  table.remove(problem.tests, index)
  return true
end

return M
