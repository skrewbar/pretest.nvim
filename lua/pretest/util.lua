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

---Directory for `.prob` and binaries: `save_dir` if set, else source file's directory.
---@param src_path string
---@return string
function M.artifact_dir(src_path)
  if M.uses_save_dir() then
    return vim.fn.expand(require("pretest.config").get().save_dir)
  end
  return vim.fn.fnamemodify(M.abspath(src_path), ":h")
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
    local ext = vim.fn.fnamemodify(path, ":e")
    if ext == "cpp" or ext == "cc" or ext == "cxx" or ext == "c" then
      ft = "cpp"
    elseif ext == "py" then
      ft = "python"
    end
  end
  return path, ft
end

return M
