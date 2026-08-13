local config = require("pretest.config")
local util = require("pretest.util")

local M = {}

---@class pretest.CaseResult
---@field verdict "Pending"|"Running"|"AC"|"WA"|"RE"|"TLE"|"CE"|"Stopped"
---@field stdout string
---@field stderr string
---@field time_ms number|nil
---@field code integer|nil

---@class pretest.ActiveRun
---@field cancelled boolean
---@field compile_obj vim.SystemObj|nil
---@field kill_current fun()|nil

---@type table<string, pretest.ActiveRun>
local active = {}

---@param args string[]
---@param ctx pretest.RunCtx
---@return string[]
local function expand_args(args, ctx)
  local out = {}
  for _, a in ipairs(args) do
    a = a:gsub("%$src", ctx.src_path)
    a = a:gsub("%$bin", ctx.bin_path)
    table.insert(out, a)
  end
  return out
end

---@param field pretest.LangExec|pretest.LangArgs|nil
---@param ctx pretest.RunCtx
---@return string|string[]|nil
local function eval_field(field, ctx)
  if type(field) == "function" then
    return field(ctx)
  end
  return field
end

---@param src_path string
---@param ft string
---@return string
function M.bin_path_for(src_path, ft)
  local dir = util.artifact_dir(src_path)
  vim.fn.mkdir(dir, "p")
  local stem = vim.fn.fnamemodify(src_path, ":t:r")
  local name
  -- Hash only when save_dir is shared; under `.pretest`, stem is enough.
  if util.uses_save_dir() then
    local hash = util.md5(src_path) or "tmp"
    name = string.format("%s_%s", stem, hash:sub(1, 8))
  else
    name = stem
  end
  local lang = config.language(ft)
  if lang and lang.compile then
    return vim.fs.joinpath(dir, name .. ".out")
  end
  return vim.fs.joinpath(dir, name)
end

---Rename the compile binary when its path changes with the source. No-op if
---the old binary is missing or the paths are identical.
---@param old_src string
---@param new_src string
---@param old_ft string
---@param new_ft string|nil
---@return boolean
function M.relocate_bin(old_src, new_src, old_ft, new_ft)
  new_ft = new_ft or old_ft
  local old_bin = M.bin_path_for(old_src, old_ft)
  local new_bin = M.bin_path_for(new_src, new_ft)
  if old_bin == new_bin then
    return true
  end
  if vim.fn.filereadable(old_bin) == 0 then
    return true
  end
  local parent = vim.fn.fnamemodify(new_bin, ":h")
  if parent ~= "" and vim.fn.isdirectory(parent) == 0 then
    vim.fn.mkdir(parent, "p")
  end
  if vim.fn.filereadable(new_bin) == 1 then
    vim.fn.delete(new_bin)
  end
  if vim.fn.rename(old_bin, new_bin) ~= 0 then
    util.notify("failed to move binary to " .. new_bin, vim.log.levels.WARN)
    return false
  end
  return true
end

---@param obj vim.SystemObj|nil
local function kill_compile(obj)
  if not obj then
    return
  end
  pcall(function()
    obj:kill("sigkill")
  end)
end

---Stop an in-flight compile/run for `src_path`. Remaining cases are not started.
---@param src_path string
---@return boolean
function M.stop(src_path)
  src_path = util.abspath(src_path)
  local job = active[src_path]
  if not job or job.cancelled then
    return false
  end
  job.cancelled = true
  kill_compile(job.compile_obj)
  if job.kill_current then
    job.kill_current()
  end
  return true
end

---@param src_path string|nil
---@return boolean
function M.is_running(src_path)
  if src_path then
    local job = active[util.abspath(src_path)]
    return job ~= nil and not job.cancelled
  end
  for _, job in pairs(active) do
    if not job.cancelled then
      return true
    end
  end
  return false
end

---@param src_path string
---@param ft string
---@param on_done fun(ok: boolean, stderr: string)
---@return vim.SystemObj|nil
function M.compile(src_path, ft, on_done)
  local lang = config.language(ft)
  if not lang then
    on_done(false, "unsupported filetype: " .. ft)
    return nil
  end
  if not lang.compile then
    on_done(true, "")
    return nil
  end

  local ctx = {
    src_path = util.abspath(src_path),
    bin_path = M.bin_path_for(src_path, ft),
  }
  local exec = eval_field(lang.compile.exec, ctx)
  if type(exec) ~= "string" then
    on_done(false, "compile.exec not configured for filetype: " .. ft)
    return nil
  end
  local raw_args = eval_field(lang.compile.args, ctx)
  local args = expand_args(type(raw_args) == "table" and raw_args or {}, ctx)
  local cmd = { exec }
  vim.list_extend(cmd, args)

  local ok, obj = pcall(vim.system, cmd, { text = true, cwd = vim.fn.fnamemodify(ctx.src_path, ":h") }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        on_done(true, result.stderr or "")
      else
        local msg = table.concat({
          result.stderr or "",
          result.stdout or "",
        }, "\n")
        on_done(false, vim.trim(msg))
      end
    end)
  end)
  if not ok then
    on_done(false, tostring(obj))
    return nil
  end
  return obj
end

---Run one testcase with CompetiTest-style timing:
---`vim.uv.now()` from after spawn/stdio setup until process exit (compile not included).
---@param src_path string
---@param ft string
---@param input string
---@param expected string
---@param time_limit_ms integer
---@param on_done fun(result: pretest.CaseResult)
---@return fun()|nil kill
function M.run_one(src_path, ft, input, expected, time_limit_ms, on_done)
  local lang = config.language(ft)
  if not lang or not lang.run then
    on_done({
      verdict = "RE",
      stdout = "",
      stderr = "unsupported filetype: " .. tostring(ft),
      time_ms = 0,
      code = -1,
    })
    return
  end

  local ctx = {
    src_path = util.abspath(src_path),
    bin_path = M.bin_path_for(src_path, ft),
  }
  local exec = eval_field(lang.run.exec, ctx)
  if type(exec) ~= "string" then
    on_done({
      verdict = "RE",
      stdout = "",
      stderr = "run.exec not configured for filetype: " .. tostring(ft),
      time_ms = 0,
      code = -1,
    })
    return
  end
  local args = eval_field(lang.run.args, ctx)
  if type(args) ~= "table" then
    args = {}
  end

  local uv = vim.uv
  local stdin = assert(uv.new_pipe(false))
  local stdout = assert(uv.new_pipe(false))
  local stderr = assert(uv.new_pipe(false))

  local stdout_chunks = {}
  local stderr_chunks = {}
  local starting_time ---@type integer|nil
  local killed = false
  local user_cancelled = false
  local timer ---@type uv.uv_timer_t|nil
  local exited, stdout_done, stderr_done = false, false, false
  local exit_code, exit_signal ---@type integer|nil, integer|nil
  local elapsed_ms = 0
  local finished = false

  local function finish()
    if finished or not exited or not stdout_done or not stderr_done then
      return
    end
    finished = true

    local out = table.concat(stdout_chunks):gsub("\r\n", "\n")
    local err = table.concat(stderr_chunks):gsub("\r\n", "\n")

    ---@type pretest.CaseResult
    local result = {
      verdict = "Pending",
      stdout = out,
      stderr = err,
      time_ms = elapsed_ms,
      code = exit_code,
    }

    local is_timeout = killed
      and time_limit_ms
      and time_limit_ms > 0
      and elapsed_ms >= time_limit_ms

    if user_cancelled then
      result.verdict = "Stopped"
    elseif is_timeout then
      result.verdict = "TLE"
    elseif exit_signal and exit_signal ~= 0 then
      result.verdict = "RE"
    elseif exit_code ~= 0 then
      result.verdict = "RE"
    elseif util.outputs_equal(result.stdout, expected) then
      result.verdict = "AC"
    else
      result.verdict = "WA"
    end

    vim.schedule(function()
      on_done(result)
    end)
  end

  ---@param pipe uv.uv_pipe_t
  local function close_pipe(pipe)
    if pipe and not pipe:is_closing() then
      pcall(function()
        pipe:read_stop()
      end)
      pipe:close()
    end
  end

  local handle ---@type uv.uv_process_t|nil
  handle = uv.spawn(exec, {
    args = args,
    cwd = vim.fn.fnamemodify(ctx.src_path, ":h"),
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    exited = true
    exit_code = code
    exit_signal = signal
    if starting_time then
      elapsed_ms = uv.now() - starting_time
    end
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
      timer = nil
    end
    if handle and not handle:is_closing() then
      handle:close()
    end
    close_pipe(stdin)
    -- Process exit can race stream EOF; force-complete so we never hang.
    if not stdout_done then
      close_pipe(stdout)
      stdout_done = true
    end
    if not stderr_done then
      close_pipe(stderr)
      stderr_done = true
    end
    finish()
  end)

  if not handle then
    stdin:close()
    stdout:close()
    stderr:close()
    on_done({
      verdict = "RE",
      stdout = "",
      stderr = "failed to spawn: " .. tostring(exec),
      time_ms = 0,
      code = -1,
    })
    return
  end

  -- Feed stdin then close (CompetiTest-style).
  uv.write(stdin, input or "", function()
    if not stdin:is_closing() then
      uv.shutdown(stdin)
    end
  end)

  uv.read_start(stdout, function(err, data)
    if err or not data then
      if not stdout_done then
        close_pipe(stdout)
        stdout_done = true
        finish()
      end
      return
    end
    stdout_chunks[#stdout_chunks + 1] = data
  end)

  uv.read_start(stderr, function(err, data)
    if err or not data then
      if not stderr_done then
        close_pipe(stderr)
        stderr_done = true
        finish()
      end
      return
    end
    stderr_chunks[#stderr_chunks + 1] = data
  end)

  if time_limit_ms and time_limit_ms > 0 then
    timer = assert(uv.new_timer())
    timer:start(time_limit_ms, 0, function()
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      if handle and not handle:is_closing() then
        killed = true
        handle:kill("sigkill")
      end
    end)
  end

  -- Start the clock after spawn/stdio setup, matching CompetiTest.
  starting_time = uv.now()

  return function()
    if finished or user_cancelled then
      return
    end
    user_cancelled = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
      timer = nil
    end
    if handle and not handle:is_closing() then
      handle:kill("sigkill")
    end
  end
end

---@param src_path string
---@param ft string
---@param problem pretest.Problem
---@param indices integer[]|nil 1-based indices; nil = all
---@param do_compile boolean
---@param hooks { on_compile_start?: fun(), on_compile_done?: fun(ok: boolean, stderr: string), on_case_start?: fun(i: integer), on_case_done?: fun(i: integer, result: pretest.CaseResult), on_all_done?: fun(cancelled: boolean) }
function M.run_tests(src_path, ft, problem, indices, do_compile, hooks)
  hooks = hooks or {}
  src_path = util.abspath(src_path)
  M.stop(src_path)

  ---@type pretest.ActiveRun
  local job = { cancelled = false }
  active[src_path] = job

  local list = indices
  if not list or #list == 0 then
    list = {}
    for i = 1, #problem.tests do
      list[i] = i
    end
  end

  local function finish_all()
    if active[src_path] ~= job then
      return
    end
    active[src_path] = nil
    if hooks.on_all_done then
      hooks.on_all_done(job.cancelled)
    end
  end

  local function is_current()
    return active[src_path] == job
  end

  local function run_queue(start_at)
    local i = start_at
    local function next_case()
      if job.cancelled or not is_current() then
        finish_all()
        return
      end
      if i > #list then
        finish_all()
        return
      end
      local idx = list[i]
      local tc = problem.tests[idx]
      if not tc then
        i = i + 1
        next_case()
        return
      end
      if hooks.on_case_start then
        hooks.on_case_start(idx)
      end
      if job.cancelled or not is_current() then
        finish_all()
        return
      end
      job.kill_current = M.run_one(src_path, ft, tc.input, tc.output, problem.timeLimit or 3000, function(result)
        job.kill_current = nil
        if not is_current() then
          return
        end
        if hooks.on_case_done then
          hooks.on_case_done(idx, result)
        end
        if job.cancelled then
          finish_all()
          return
        end
        i = i + 1
        next_case()
      end)
    end
    next_case()
  end

  if not do_compile then
    run_queue(1)
    return
  end

  if hooks.on_compile_start then
    hooks.on_compile_start()
  end
  job.compile_obj = M.compile(src_path, ft, function(ok, stderr)
    job.compile_obj = nil
    if job.cancelled or not is_current() then
      finish_all()
      return
    end
    if hooks.on_compile_done then
      hooks.on_compile_done(ok, stderr)
    end
    if not ok then
      local ce = {
        verdict = "CE",
        stdout = "",
        stderr = stderr,
        time_ms = 0,
        code = 1,
      }
      for _, idx in ipairs(list) do
        if hooks.on_case_done then
          hooks.on_case_done(idx, ce)
        end
      end
      finish_all()
      return
    end
    run_queue(1)
  end)
end

return M
