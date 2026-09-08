local config = require("pretest.config")
local prob = require("pretest.prob")
local ui = require("pretest.ui")
local util = require("pretest.util")

local M = {}

---@alias pretest.ReceiveMode "current"|"problem"|"contest"|"persistently"

local HTTP_OK = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

---@class pretest.CompanionState
---@field mode pretest.ReceiveMode
---@field port integer
---@field server uv.uv_tcp_t
---@field bufnr integer|nil
---@field batches table<string, { size: integer, tasks: pretest.CCTask[] }>
---@field queue pretest.CCTask[][]
---@field busy boolean
---@field leave_au integer|nil

---@type pretest.CompanionState|nil
local state = nil

---@param path string
---@return boolean
local function supported_source(path)
  return util.supported_filetype(util.filetype_from_path(path))
end

---@param s string
---@return string
local function slugify(s)
  s = tostring(s or "")
  s = s:gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
  s = s:gsub("[\r\n%z]", "")
  s = s:gsub("%s+", "_")
  s = s:gsub("[^%w_%-]", "_")
  s = s:gsub("_+", "_")
  s = s:gsub("^[_%-]+", ""):gsub("[_%-]+$", "")
  if s == "" then
    return "problem"
  end
  return s
end

---@param group string
---@return string, string
local function split_group(group)
  group = group or ""
  local hyphen = group:find(" - ", 1, true)
  if not hyphen then
    return group, "unknown_contest"
  end
  return group:sub(1, hyphen - 1), group:sub(hyphen + 3)
end

---Split "G. Castle Defense" / "A - Welcome" into index + remainder.
---@param name string
---@return string|nil, string
local function split_index_title(name)
  name = vim.trim(tostring(name or ""))
  name = name:gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
  local index, rest = name:match("^([A-Za-z][A-Za-z0-9]*)%s*[%.%-%:]%s*(.+)$")
  if index and rest then
    return index, vim.trim(rest)
  end
  index, rest = name:match("^(%d+)%s*[%.%-%:]%s*(.+)$")
  if index and rest then
    return index, vim.trim(rest)
  end
  return nil, name
end

---@param task pretest.CCTask
---@return string
local function task_class(task)
  local java = task.languages and task.languages.java
  if java and type(java.taskClass) == "string" and java.taskClass ~= "" then
    return slugify(java.taskClass)
  end
  return slugify(task.name or "problem")
end

---@param task pretest.CCTask
---@param ext string
---@return table<string, string>
local function placeholders(task, ext)
  local judge, contest = split_group(task.group or "")
  local index, rest = split_index_title(task.name or "")
  local slug = slugify(rest)
  local problem = index and (index .. "_" .. slug) or slug
  local file = index or slug
  return {
    cwd = vim.fn.getcwd(),
    home = vim.uv.os_homedir() or "",
    name = slugify(task.name or "problem"),
    index = index or "",
    slug = slug,
    problem = problem,
    file = file,
    task_class = task_class(task),
    ext = ext,
    group = slugify(task.group or ""),
    judge = slugify(judge),
    contest = slugify(contest),
  }
end

---@param spec pretest.CompanionPath
---@param task pretest.CCTask
---@param ext string
---@return string|nil
local function expand_path(spec, task, ext)
  if type(spec) == "function" then
    local ok, result = pcall(spec, task, ext)
    if not ok or type(result) ~= "string" or result == "" then
      return nil
    end
    return result
  end
  if type(spec) ~= "string" then
    return nil
  end
  local vars = placeholders(task, ext)
  return (spec:gsub("{([%w_]+)}", function(key)
    return vars[key] or ""
  end))
end

---@param ext string
---@return string|nil
local function template_for_ext(ext)
  local tmpl = config.options.companion.template
  if type(tmpl) == "string" and tmpl ~= "" then
    return vim.fn.expand(tmpl)
  end
  if type(tmpl) == "table" then
    local path = tmpl[ext]
    if type(path) == "string" and path ~= "" then
      return vim.fn.expand(path)
    end
  end
  return nil
end

---@param filepath string
---@return boolean
local function confirm_overwrite(filepath)
  if vim.fn.filereadable(filepath) == 0 then
    return true
  end
  local choice = vim.fn.confirm('Overwrite "' .. filepath .. '"?', "&Yes\n&No", 2)
  return choice == 1
end

---@param filepath string
---@param task pretest.CCTask
---@return pretest.Problem|nil
local function write_source_and_prob(filepath, task)
  local ext = vim.fn.fnamemodify(filepath, ":e")
  local tmpl = template_for_ext(ext)
  local content = ""
  if tmpl then
    if vim.fn.filereadable(tmpl) == 1 then
      content = util.read_file(tmpl) or ""
    else
      util.notify("template file not found: " .. tmpl, vim.log.levels.WARN)
    end
  end
  local ok, err = util.write_file(filepath, content)
  if not ok then
    util.notify("failed to write source: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  local problem = prob.from_companion(task, filepath)
  if not prob.save(problem) then
    return nil
  end
  return problem
end

---@param bufnr integer
---@return string|nil path
---@return string|nil filetype # nil only when path is nil; otherwise string (possibly "")
local function source_from_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, nil
  end
  return util.source_from_buf(bufnr)
end

---@param bufnr integer
---@param task pretest.CCTask
---@return boolean
local function store_testcases(bufnr, task)
  local path, ft = source_from_bufnr(bufnr)
  if not path then
    util.notify("no file in current buffer", vim.log.levels.ERROR)
    return false
  end
  if not util.supported_filetype(ft) then
    util.notify("unsupported filetype: " .. util.filetype_label(ft), vim.log.levels.ERROR)
    return false
  end

  local existing, ppath = prob.load_or_create(path)
  -- Companion payload is authoritative for name, limits, and other metadata.
  local incoming = prob.from_companion(task, path)
  local cfg = config.options.companion

  if #existing.tests > 0 and not cfg.replace_testcases then
    local choice = vim.fn.confirm(
      "Some testcases already exist. Keep them along the new ones?",
      "&Keep\n&Replace\n&Cancel",
      1
    )
    if choice == 0 or choice == 3 then
      return false
    end
    if choice == 1 then
      local merged = vim.deepcopy(existing.tests)
      for _, tc in ipairs(incoming.tests) do
        merged[#merged + 1] = tc
      end
      incoming.tests = merged
    end
  end

  if not prob.save(incoming, ppath) then
    return false
  end
  return ui.apply_problem(path, incoming)
end

---@param filepath string
---@param task pretest.CCTask
---@param do_open boolean
---@return boolean
local function store_problem_at(filepath, task, do_open)
  filepath = util.abspath(filepath)
  if not confirm_overwrite(filepath) then
    return false
  end
  local problem = write_source_and_prob(filepath, task)
  if not problem then
    return false
  end
  if not supported_source(filepath) then
    util.notify("unsupported source extension: " .. vim.fn.fnamemodify(filepath, ":e"), vim.log.levels.WARN)
    prob.save(problem)
    return true
  end
  if do_open then
    return ui.apply_problem(filepath, problem)
  end
  return prob.save(problem)
end

---@param task pretest.CCTask
---@param finished fun()
local function store_single_problem(task, finished)
  local cfg = config.options.companion
  local ext = cfg.extension
  local evaluated = expand_path(cfg.problem_path, task, ext)
  if not evaluated then
    util.notify("problem_path evaluation failed for '" .. tostring(task.name) .. "'", vim.log.levels.ERROR)
    finished()
    return
  end

  local function write(path)
    if not path or path == "" then
      finished()
      return
    end
    store_problem_at(path, task, cfg.open)
    finished()
  end

  if cfg.prompt_path then
    vim.ui.input({ prompt = "Problem path: ", default = evaluated }, write)
  else
    write(evaluated)
  end
end

---@param tasks pretest.CCTask[]
---@param finished fun()
local function store_contest(tasks, finished)
  local cfg = config.options.companion
  local ext = cfg.extension
  local evaluated = expand_path(cfg.contest_dir, tasks[1], ext)
  if not evaluated then
    util.notify("contest_dir evaluation failed", vim.log.levels.ERROR)
    finished()
    return
  end

  local function write_all(directory)
    if not directory or directory == "" then
      finished()
      return
    end
    directory = util.abspath(directory)
    local first = nil
    for _, task in ipairs(tasks) do
      local rel = expand_path(cfg.contest_problem_path, task, ext)
      if not rel or rel == "" then
        util.notify("contest_problem_path evaluation failed for '" .. tostring(task.name) .. "'", vim.log.levels.WARN)
      else
        local filepath = util.abspath(vim.fs.joinpath(directory, rel))
        if confirm_overwrite(filepath) then
          local problem = write_source_and_prob(filepath, task)
          if problem and not first then
            first = { path = filepath, problem = problem }
          end
        end
      end
    end
    if first and cfg.open and supported_source(first.path) then
      ui.apply_problem(first.path, first.problem)
    elseif first then
      util.notify(string.format("saved contest (%d tasks) under %s", #tasks, directory))
    end
    finished()
  end

  if cfg.prompt_path then
    vim.ui.input({ prompt = "Contest directory: ", default = evaluated }, write_all)
  else
    write_all(evaluated)
  end
end

---@param tasks pretest.CCTask[]
---@param finished fun()
local function handle_batch(tasks, finished)
  if not state or #tasks == 0 then
    finished()
    return
  end
  local mode = state.mode
  local bufnr = state.bufnr
  if mode ~= "persistently" then
    M.stop()
  end

  if mode == "current" then
    if store_testcases(bufnr or vim.api.nvim_get_current_buf(), tasks[1]) then
      util.notify("received: " .. tostring(tasks[1].name))
    end
    finished()
  elseif mode == "problem" then
    util.notify("problem received: " .. tostring(tasks[1].name))
    store_single_problem(tasks[1], finished)
  elseif mode == "contest" then
    util.notify(string.format("contest received (%d tasks)", #tasks))
    store_contest(tasks, finished)
  else
    if #tasks > 1 then
      util.notify(string.format("contest received (%d tasks)", #tasks))
      store_contest(tasks, finished)
    else
      local name = tostring(tasks[1].name)
      local choice = vim.fn.confirm(
        "One task received (" .. name .. ").\nWrite to the current file or create a new problem file?",
        "&This file\n&Problem\n&Cancel",
        2
      )
      if choice == 1 then
        local s = ui.get_session()
        local bufnr = (s and s.src_bufnr) or vim.api.nvim_get_current_buf()
        store_testcases(bufnr, tasks[1])
        finished()
      elseif choice == 2 then
        store_single_problem(tasks[1], finished)
      else
        finished()
      end
    end
  end
end

local function process_queue()
  if not state or state.busy or #state.queue == 0 then
    return
  end
  state.busy = true
  local batch = table.remove(state.queue, 1)
  handle_batch(batch, function()
    if state then
      state.busy = false
      process_queue()
    end
  end)
end

---@param task pretest.CCTask
local function insert_task(task)
  if not state or type(task) ~= "table" then
    return
  end
  local batch = task.batch
  local id = batch and batch.id or tostring(vim.uv.hrtime())
  local size = (batch and tonumber(batch.size)) or 1
  if not state.batches[id] then
    state.batches[id] = { size = size, tasks = {} }
  end
  local slot = state.batches[id]
  slot.tasks[#slot.tasks + 1] = task
  if #slot.tasks >= slot.size then
    local tasks = slot.tasks
    state.batches[id] = nil
    state.queue[#state.queue + 1] = tasks
    process_queue()
  end
end

---@param buf string
---@return string|nil body
local function parse_http_body(buf)
  local start_i, end_i = buf:find("\r\n\r\n", 1, true)
  if not start_i then
    start_i, end_i = buf:find("\n\n", 1, true)
  end
  if not start_i or not end_i then
    return nil
  end
  local headers = buf:sub(1, start_i - 1)
  local body = buf:sub(end_i + 1)
  local len = tonumber(headers:match("[Cc]ontent%-[Ll]ength:%s*(%d+)"))
  if len then
    if #body < len then
      return nil
    end
    return body:sub(1, len)
  end
  return body
end

---@param client uv.uv_tcp_t
local function on_client(client)
  local chunks = {}
  local completed = false

  local function finish(body)
    if completed then
      return
    end
    completed = true
    client:write(HTTP_OK, function()
      pcall(function()
        client:shutdown()
        client:close()
      end)
    end)
    if not body or body == "" then
      return
    end
    vim.schedule(function()
      local ok, task = pcall(vim.json.decode, body)
      if ok and type(task) == "table" then
        insert_task(task)
      end
    end)
  end

  client:read_start(function(err, chunk)
    if err then
      finish(nil)
      return
    end
    if chunk then
      chunks[#chunks + 1] = chunk
      local body = parse_http_body(table.concat(chunks))
      if body then
        finish(body)
      end
      return
    end
    finish(parse_http_body(table.concat(chunks)))
  end)
end

function M.stop()
  if not state then
    return false
  end
  local server = state.server
  if state.leave_au then
    pcall(vim.api.nvim_del_autocmd, state.leave_au)
  end
  state = nil
  if server and not server:is_closing() then
    server:close()
  end
  return true
end

---User-facing fragment after "receive"/"receiving" (`""` for current-file mode).
---@param mode pretest.ReceiveMode
---@return string
local function mode_phrase(mode)
  if mode == "current" then
    return ""
  end
  return " " .. mode
end

function M.status()
  if not state then
    util.notify("receiving not enabled")
    return
  end
  util.notify(
    string.format("receiving%s, listening on 127.0.0.1:%d", mode_phrase(state.mode), state.port)
  )
end

---@param mode pretest.ReceiveMode
---@return boolean
function M.start(mode)
  if state then
    util.notify(
      "already receiving" .. mode_phrase(state.mode) .. "; :Pretest receive stop first",
      vim.log.levels.WARN
    )
    return false
  end

  local bufnr = nil
  if mode == "current" then
    bufnr = vim.api.nvim_get_current_buf()
    local path, ft = source_from_bufnr(bufnr)
    if not path then
      util.notify("open a source file first", vim.log.levels.ERROR)
      return false
    end
    if not util.supported_filetype(ft) then
      util.notify("unsupported filetype: " .. util.filetype_label(ft), vim.log.levels.ERROR)
      return false
    end
  end

  local port = config.options.companion.port
  local server = vim.uv.new_tcp()
  if not server then
    util.notify("failed to create TCP socket", vim.log.levels.ERROR)
    return false
  end

  local bind_ok, bind_err = server:bind("127.0.0.1", port)
  if not bind_ok then
    server:close()
    util.notify(
      string.format(
        "cannot bind 127.0.0.1:%d (%s) — is CPH, CompetiTest, or another Neovim listening?",
        port,
        tostring(bind_err)
      ),
      vim.log.levels.ERROR
    )
    return false
  end

  local listen_ok, listen_err = server:listen(128, function(err)
    if err or not state or state.server ~= server then
      return
    end
    local client = vim.uv.new_tcp()
    if not client then
      return
    end
    server:accept(client)
    on_client(client)
  end)
  if not listen_ok then
    server:close()
    util.notify("cannot listen on port " .. tostring(port) .. ": " .. tostring(listen_err), vim.log.levels.ERROR)
    return false
  end

  state = {
    mode = mode,
    port = port,
    server = server,
    bufnr = bufnr,
    batches = {},
    queue = {},
    busy = false,
    leave_au = vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        M.stop()
      end,
    }),
  }

  util.notify(
    string.format(
      "ready to receive%s on 127.0.0.1:%d. Press the green plus in your browser.",
      mode_phrase(mode),
      port
    )
  )
  return true
end

return M
