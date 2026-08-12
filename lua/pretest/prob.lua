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
  local hash = util.md5(src_path)
  if not hash then
    util.notify("failed to compute md5 for srcPath", vim.log.levels.ERROR)
    return nil
  end
  local base = vim.fn.fnamemodify(src_path, ":t")
  local dir = util.artifact_dir(src_path)
  return vim.fs.joinpath(dir, string.format(".%s_%s.prob", base, hash))
end

---@param src_path string
---@return pretest.Problem
function M.new_local(src_path)
  src_path = util.abspath(src_path)
  local stem = vim.fn.fnamemodify(src_path, ":t:r")
  local cfg = config.get()
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
  data.timeLimit = data.timeLimit or config.get().default_time_limit
  data.memoryLimit = data.memoryLimit or config.get().default_memory_limit
  data.name = data.name or ("Local: " .. vim.fn.fnamemodify(src_path, ":t:r"))
  data.url = data.url or src_path
  data.group = data.group or "local"
  if data.interactive == nil then
    data.interactive = false
  end
  if data["local"] == nil then
    data["local"] = true
  end

  for _, tc in ipairs(data.tests) do
    tc.input = util.ensure_string(tc.input)
    tc.output = util.ensure_string(tc.output)
    tc.id = tc.id or math.floor(vim.uv.hrtime() / 1000)
  end

  return data --[[@as pretest.Problem]], path
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

---@param problem pretest.Problem
---@return pretest.TestCase
function M.add_testcase(problem)
  local tc = {
    id = math.floor(vim.uv.hrtime() / 1000),
    input = "",
    output = "",
  }
  table.insert(problem.tests, tc)
  return tc
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
