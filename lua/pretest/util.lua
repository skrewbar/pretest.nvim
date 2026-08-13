local M = {}

---@param msg string
---@param level integer|nil
function M.notify(msg, level)
  vim.notify("Pretest.nvim: " .. msg, level or vim.log.levels.INFO, { title = "Pretest" })
end

---@param path string
---@return string
function M.abspath(path)
  return vim.fn.fnamemodify(path, ":p")
end

---Whether artifacts are stored in a shared `save_dir` (names may collide).
---@return boolean
function M.uses_save_dir()
  local save_dir = require("pretest.config").get().save_dir
  return type(save_dir) == "string" and save_dir ~= ""
end

---Directory for `.prob` and binaries: `save_dir` if set, else `{src_dir}/.pretest`.
---@param src_path string
---@return string
function M.artifact_dir(src_path)
  if M.uses_save_dir() then
    return vim.fn.expand(require("pretest.config").get().save_dir)
  end
  local src_dir = vim.fn.fnamemodify(M.abspath(src_path), ":h")
  return vim.fs.joinpath(src_dir, ".pretest")
end

---MD5 of a string (matches common .prob naming: md5(srcPath)).
---@param str string
---@return string|nil
function M.md5(str)
  if vim.fn.executable("md5") == 1 then
    local r = vim.system({ "md5", "-q", "-s", str }, { text = true }):wait()
    if r.code == 0 and r.stdout and r.stdout ~= "" then
      return vim.trim(r.stdout)
    end
  end

  if vim.fn.executable("openssl") == 1 then
    local r = vim.system({ "openssl", "md5" }, { stdin = str, text = true }):wait()
    if r.code == 0 and r.stdout then
      local hex = r.stdout:match("([a-fA-F0-9][a-fA-F0-9]+)%s*$")
      if hex then
        return hex:lower()
      end
    end
  end

  if vim.fn.executable("md5sum") == 1 then
    local r = vim.system({ "md5sum" }, { stdin = str, text = true }):wait()
    if r.code == 0 and r.stdout then
      local hex = r.stdout:match("^([a-fA-F0-9]+)")
      if hex then
        return hex:lower()
      end
    end
  end

  return nil
end

---@param s string|nil
---@return string
function M.ensure_string(s)
  if s == nil then
    return ""
  end
  return tostring(s)
end

---Split into lines, preserving a trailing empty line from a final newline.
---Round-trips with `join_lines` so Input/Expected are not silently trimmed.
---@param s string|nil
---@return string[]
function M.split_lines(s)
  s = M.ensure_string(s)
  if s == "" then
    return { "" }
  end
  local lines = vim.split(s, "\n", { plain = true })
  if #lines == 0 then
    return { "" }
  end
  return lines
end

---Join buffer lines back to a string. Preserves trailing empty lines / final newline.
---@param lines string[]
---@return string
function M.join_lines(lines)
  if not lines or #lines == 0 then
    return ""
  end
  return table.concat(lines, "\n")
end

---Normalize for AC/WA: strip trailing whitespace per line and trailing empty lines.
---@param s string|nil
---@return string
function M.normalize_output(s)
  local lines = vim.split(M.ensure_string(s):gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("%s+$", "")
  end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

---@param a string|nil
---@param b string|nil
---@return boolean
function M.outputs_equal(a, b)
  return M.normalize_output(a) == M.normalize_output(b)
end

---@param path string
---@return string|nil
function M.read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

---@param path string
---@param content string
---@return boolean, string|nil
function M.write_file(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  local f, err = io.open(path, "w")
  if not f then
    return false, err
  end
  f:write(content)
  f:close()
  return true
end

---`(0, 1]` is a fraction of `total`; `> 1` is absolute cells.
---@param n number|nil
---@param total number
---@return number|nil
local function to_cells(n, total)
  if type(n) ~= "number" or n ~= n or n <= 0 or n == math.huge then
    return nil
  end
  if n <= 1 then
    return total * n
  end
  return n
end

---Resolve a size number, clamp to min/max (same relative/absolute rules), then to `[1, total]`.
---@param spec number|nil
---@param min_spec number|nil
---@param max_spec number|nil
---@param total number
---@param fallback number|nil
---@return integer
function M.resolve_size(spec, min_spec, max_spec, total, fallback)
  local size = to_cells(spec, total) or to_cells(fallback, total) or 1
  local min_v = to_cells(min_spec, total)
  local max_v = to_cells(max_spec, total)
  if min_v then
    size = math.max(size, min_v)
  end
  if max_v then
    size = math.min(size, max_v)
  end
  total = math.max(1, math.floor(total))
  return math.max(1, math.min(math.floor(size + 1e-9), total))
end

---@param ft string|nil
---@return boolean
function M.supported_filetype(ft)
  return require("pretest.config").language(ft) ~= nil
end

---@param path string
---@return string|nil
function M.filetype_from_path(path)
  local languages = require("pretest.config").get().languages or {}
  local detected = vim.filetype.match({ filename = path })
  if detected and languages[detected] then
    return detected
  end

  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  if ext ~= "" then
    for ft, lang in pairs(languages) do
      local exts = type(lang) == "table" and lang.extensions
      if type(exts) == "table" then
        for _, e in ipairs(exts) do
          if type(e) == "string" and e:lower() == ext then
            return ft
          end
        end
      end
    end
    if languages[ext] then
      return ext
    end
  end

  if detected and detected ~= "" then
    return detected
  end
  return nil
end

---@param bufnr integer|nil
---@return string|nil, string|nil # path, filetype
function M.source_from_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil, nil
  end
  local path = M.abspath(name)
  local ft = vim.bo[bufnr].filetype
  if ft == "" then
    ft = nil
  end
  if not M.supported_filetype(ft) then
    ft = M.filetype_from_path(path) or ft
  end
  return path, ft
end

return M
