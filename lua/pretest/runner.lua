local config = require("pretest.config")
local util = require("pretest.util")

local M = {}

---@class pretest.CaseResult
---@field verdict "Pending"|"Running"|"AC"|"WA"|"RE"|"TLE"|"MLE"|"CE"|"Stopped"
---@field stdout string
---@field stderr string
---@field time_ms number|nil
---@field memory_kb number|nil peak RSS in KiB
---@field code integer|nil
---@field signal integer|string|nil
---@field reason string|nil
---@field reason_detail string|nil

---@class pretest.ActiveRun
---@field cancelled boolean
---@field compiling boolean
---@field compile_obj vim.SystemObj|nil
---@field kill_current fun()|nil

---@type table<string, pretest.ActiveRun>
local active = {}

local UNAME = ((vim.uv.os_uname() or {}).sysname) or ""
local IS_WINDOWS = UNAME == "Windows_NT" or UNAME:find("Windows", 1, true) ~= nil
local IS_DARWIN = UNAME == "Darwin"

local HAS_PROCFS = (function()
  local f = io.open("/proc/self/statm", "r")
  if not f then
    return false
  end
  f:close()
  return true
end)()

---@param timer uv.uv_timer_t|nil
local function close_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

---@return integer
local function page_size_bytes()
  local n = vim.uv.os_getpagesize and vim.uv.os_getpagesize()
  if type(n) == "number" and n > 0 then
    return n
  end
  return 4096
end

local time_bin_cached ---@type string|false|nil
local gnu_time_cached ---@type boolean|nil

---@return string|nil
local function time_bin()
  if time_bin_cached ~= nil then
    return time_bin_cached or nil
  end
  if vim.fn.executable("/usr/bin/time") == 1 then
    time_bin_cached = "/usr/bin/time"
    return time_bin_cached
  end
  if vim.fn.executable("time") == 1 then
    local p = vim.fn.exepath("time")
    if type(p) == "string" and p ~= "" then
      time_bin_cached = p
      return p
    end
  end
  time_bin_cached = false
  return nil
end

---@param bin string
---@return boolean
local function gnu_time_works(bin)
  if gnu_time_cached ~= nil then
    return gnu_time_cached
  end
  local true_bin = (vim.fn.executable("/bin/true") == 1 and "/bin/true")
    or (vim.fn.executable("true") == 1 and "true")
    or nil
  if not true_bin then
    gnu_time_cached = false
    return false
  end
  local r = vim.system({ bin, "-f", "%M", "-o", "/dev/null", true_bin }, { text = true }):wait()
  gnu_time_cached = r.code == 0
  return gnu_time_cached
end

---Peak RSS in KiB from `/proc/<pid>/status` `VmHWM`, else current RSS from `statm`.
---@param pid integer
---@return integer|nil
local function rss_from_procfs(pid)
  local status = io.open("/proc/" .. tostring(pid) .. "/status", "r")
  if status then
    local hwm
    for line in status:lines() do
      local kb = tonumber(line:match("^VmHWM:%s*(%d+)"))
      if kb then
        hwm = kb
        break
      end
    end
    status:close()
    if hwm then
      return hwm
    end
  end

  local f = io.open("/proc/" .. tostring(pid) .. "/statm", "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  if not line then
    return nil
  end
  local pages = tonumber(line:match("^%S+%s+(%S+)"))
  if not pages then
    return nil
  end
  return math.floor(pages * page_size_bytes() / 1024)
end

---Strip BSD `time -l` rusage trailer. Returns program stderr and peak KiB.
---@param err string
---@return string
---@return integer|nil
local function split_bsd_time_stderr(err)
  local lines = vim.split(err, "\n", { plain = true })
  local max_i, bytes
  for i = #lines, 1, -1 do
    local n = lines[i]:match("(%d+)%s+maximum resident set size")
    if n then
      max_i = i
      bytes = tonumber(n)
      break
    end
  end
  if not max_i then
    return err, nil
  end
  local start_i = max_i
  for i = max_i, 1, -1 do
    if lines[i]:match("%f[%w]real%f[%W]") then
      start_i = i
      break
    end
  end
  local prog
  if start_i > 1 then
    prog = table.concat(lines, "\n", 1, start_i - 1)
  else
    prog = ""
  end
  local kb = bytes and math.floor(bytes / 1024) or nil
  return prog, kb
end

---@param cmd string
---@param args string[]
---@param on_done fun(out: string|nil)
---@param timeout_ms integer|nil
---@return fun()|nil cancel
local function spawn_capture_stdout(cmd, args, on_done, timeout_ms)
  local uv = vim.uv
  local stdout = uv.new_pipe(false)
  if not stdout then
    on_done(nil)
    return
  end
  local chunks = {}
  local proc ---@type uv.uv_process_t|nil
  local timer ---@type uv.uv_timer_t|nil
  local done = false
  local function finish(out)
    if done then
      return
    end
    done = true
    close_timer(timer)
    if stdout and not stdout:is_closing() then
      pcall(function()
        stdout:read_stop()
      end)
      stdout:close()
    end
    if proc and not proc:is_closing() then
      proc:close()
    end
    on_done(out)
  end
  proc = uv.spawn(cmd, { args = args, stdio = { nil, stdout, nil } }, function()
    finish(table.concat(chunks))
  end)
  if not proc then
    finish(nil)
    return
  end
  if timeout_ms and timeout_ms > 0 then
    timer = uv.new_timer()
    if timer then
      timer:start(timeout_ms, 0, function()
        if proc and not proc:is_closing() then
          pcall(function()
            proc:kill("sigkill")
          end)
        end
        finish(nil)
      end)
    end
  end
  uv.read_start(stdout, function(_, data)
    if data then
      chunks[#chunks + 1] = data
    end
  end)
  return function()
    if proc and not proc:is_closing() then
      pcall(function()
        proc:kill("sigkill")
      end)
    end
    finish(nil)
  end
end

---@param script string
---@param on_done fun(out: string|nil)
---@param timeout_ms integer|nil
---@return fun()|nil cancel
local function win_powershell(script, on_done, timeout_ms)
  local args = { "-NoProfile", "-NonInteractive", "-Command", script }
  local current_cancel ---@type fun()|nil
  local settled = false
  local cancelled = false
  local function settle(out)
    if settled then
      return
    end
    settled = true
    on_done(out)
  end
  local function on_ps(out)
    if cancelled or settled then
      return
    end
    if out and out:match("%d+") then
      settle(out)
      return
    end
    local c2 = spawn_capture_stdout("powershell.exe", args, settle, timeout_ms)
    if c2 then
      current_cancel = c2
    else
      settle(nil)
    end
  end
  local c = spawn_capture_stdout("powershell", args, on_ps, timeout_ms)
  if c then
    current_cancel = c
  end
  return function()
    cancelled = true
    if current_cancel then
      current_cancel()
    end
    settle(nil)
  end
end

local function parse_peak_bytes(out)
  local n = tonumber((out or ""):match("%d+"))
  if n then
    return math.floor(n / 1024)
  end
end

---One-shot PeakWorkingSet64 (bytes → KiB). Call before closing the uv process handle.
---@param pid integer
---@param on_done fun(kb: integer|nil)
---@return fun()|nil cancel
local function win_peak_working_set_kb(pid, on_done)
  return win_powershell(
    string.format("(Get-Process -Id %d).PeakWorkingSet64", pid),
    function(out)
      on_done(parse_peak_bytes(out))
    end,
    4000
  )
end

---Attach while the process is alive, then read peak after exit (Get-Process running-only fallback).
---@param pid integer
---@param on_done fun(kb: integer|nil)
---@return fun()|nil cancel
local function win_watch_peak_kb(pid, on_done)
  local script = string.format(
    "$p=$null; foreach($i in 1..200){ try { $p=Get-Process -Id %d -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 10 } }; if(-not $p){ exit 1 }; [void]$p.WaitForExit(); Write-Output $p.PeakWorkingSet64",
    pid
  )
  return win_powershell(script, function(out)
    on_done(parse_peak_bytes(out))
  end)
end

---@param kb integer|nil
---@return string
local function format_rss(kb)
  if not kb or kb < 0 then
    return "unknown"
  end
  if kb >= 1024 then
    return string.format("%dMB", math.floor(kb / 1024 + 0.5))
  end
  return string.format("%dKB", kb)
end

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
---@param new_ft string|nil # empty or nil → use old_ft
---@return boolean
function M.relocate_bin(old_src, new_src, old_ft, new_ft)
  if new_ft == nil or new_ft == "" then
    new_ft = old_ft
  end
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

---True while an async compile process is in flight for `src_path`.
---@param src_path string|nil
---@return boolean
function M.is_compiling(src_path)
  if not src_path then
    return false
  end
  local job = active[util.abspath(src_path)]
  return job ~= nil and not job.cancelled and job.compiling == true
end

---@param src_path string
---@param ft string
---@param on_done fun(ok: boolean, stderr: string)
---@return vim.SystemObj|nil
function M.compile(src_path, ft, on_done)
  local lang = config.language(ft)
  if not lang then
    on_done(false, "unsupported filetype: " .. util.filetype_label(ft))
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
    on_done(false, "compile.exec not configured for filetype: " .. util.filetype_label(ft))
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
---@param memory_limit_mb integer|fun(result: pretest.CaseResult)|nil
---@param on_done fun(result: pretest.CaseResult)|nil
---@return fun()|nil kill
function M.run_one(src_path, ft, input, expected, time_limit_ms, memory_limit_mb, on_done)
  if type(memory_limit_mb) == "function" then
    on_done = memory_limit_mb
    memory_limit_mb = nil
  end
  ---@cast on_done fun(result: pretest.CaseResult)
  ---@cast memory_limit_mb integer|nil

  local lang = config.language(ft)
  if not lang or not lang.run then
    on_done(util.attach_re_cause({
      verdict = "RE",
      stdout = "",
      stderr = "unsupported filetype: " .. util.filetype_label(ft),
      time_ms = 0,
      code = -1,
    }))
    return
  end

  local ctx = {
    src_path = util.abspath(src_path),
    bin_path = M.bin_path_for(src_path, ft),
  }
  local exec = eval_field(lang.run.exec, ctx)
  if type(exec) ~= "string" then
    on_done(util.attach_re_cause({
      verdict = "RE",
      stdout = "",
      stderr = "run.exec not configured for filetype: " .. util.filetype_label(ft),
      time_ms = 0,
      code = -1,
    }))
    return
  end
  local args = eval_field(lang.run.args, ctx)
  if type(args) ~= "table" then
    args = {}
  end

  ---@type "gnu_time"|"bsd_time"|"procfs"|"win_peak"|nil
  local mem_mode
  local rss_path ---@type string|nil
  local time_wrap = false
  if memory_limit_mb and memory_limit_mb > 0 then
    if IS_WINDOWS then
      mem_mode = "win_peak"
    else
      local tbin = time_bin()
      if IS_DARWIN and tbin then
        mem_mode = "bsd_time"
        local wrapped = { "-l", exec }
        vim.list_extend(wrapped, args)
        exec = tbin
        args = wrapped
        time_wrap = true
      elseif tbin and gnu_time_works(tbin) then
        mem_mode = "gnu_time"
        rss_path = vim.fn.tempname() .. ".rss"
        local wrapped = { "-f", "%M", "-o", rss_path, exec }
        vim.list_extend(wrapped, args)
        exec = tbin
        args = wrapped
        time_wrap = true
      elseif HAS_PROCFS then
        mem_mode = "procfs"
      end
    end
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
  local tle_timer ---@type uv.uv_timer_t|nil
  local mem_timer ---@type uv.uv_timer_t|nil
  local win_peak_pending = false
  local win_watch_done = true
  local win_ps_cancels = {}
  local win_give_up ---@type uv.uv_timer_t|nil
  local exited, stdout_done, stderr_done = false, false, false
  local exit_code, exit_signal ---@type integer|nil, integer|string|nil
  local elapsed_ms = 0
  local finished = false
  local peak_kb ---@type integer|nil
  local handle ---@type uv.uv_process_t|nil
  local pid ---@type integer|nil

  local function stop_timers()
    close_timer(tle_timer)
    close_timer(mem_timer)
    close_timer(win_give_up)
    tle_timer, mem_timer, win_give_up = nil, nil, nil
  end

  local function cancel_win_ps()
    local list = win_ps_cancels
    win_ps_cancels = {}
    for _, fn in ipairs(list) do
      pcall(fn)
    end
  end

  local function kill_group()
    if pid then
      pcall(function()
        uv.kill(-pid, "sigkill")
      end)
    end
  end

  local function kill_run()
    if handle and not handle:is_closing() then
      killed = true
      if time_wrap then
        kill_group()
      end
      handle:kill("sigkill")
    end
    stop_timers()
  end

  local function note_rss(kb)
    if type(kb) ~= "number" or kb < 0 then
      return
    end
    if not peak_kb or kb > peak_kb then
      peak_kb = kb
    end
  end

  local function sample_rss()
    if exited or user_cancelled or finished or not pid or mem_mode ~= "procfs" then
      return
    end
    note_rss(rss_from_procfs(pid))
  end

  local function finish()
    if finished or not exited or not stdout_done or not stderr_done then
      return
    end
    if win_peak_pending then
      return
    end
    if mem_mode == "win_peak" and not user_cancelled and not peak_kb and not win_watch_done then
      return
    end
    finished = true
    stop_timers()
    cancel_win_ps()

    local out = table.concat(stdout_chunks):gsub("\r\n", "\n")
    local err = table.concat(stderr_chunks):gsub("\r\n", "\n")

    if mem_mode == "bsd_time" then
      local prog_err, kb = split_bsd_time_stderr(err)
      err = prog_err
      if kb then
        peak_kb = kb
      end
    elseif rss_path then
      local f = io.open(rss_path, "r")
      if f then
        local n = tonumber((f:read("*a") or ""):match("%d+"))
        f:close()
        if n then
          peak_kb = n
        end
      end
      pcall(os.remove, rss_path)
    end

    ---@type pretest.CaseResult
    local result = {
      verdict = "Pending",
      stdout = out,
      stderr = err,
      time_ms = elapsed_ms,
      memory_kb = peak_kb,
      code = exit_code,
      signal = exit_signal,
    }

    local is_timeout = killed
      and time_limit_ms
      and time_limit_ms > 0
      and elapsed_ms >= time_limit_ms
    local limit_mb = memory_limit_mb
    local over_mem = limit_mb
      and limit_mb > 0
      and peak_kb
      and peak_kb > limit_mb * 1024

    if user_cancelled then
      result.verdict = "Stopped"
    elseif over_mem then
      result.verdict = "MLE"
      result.reason = format_rss(peak_kb)
      result.reason_detail = string.format(
        "peak RSS %s (limit %dMB)",
        format_rss(peak_kb),
        limit_mb or 0
      )
    elseif is_timeout then
      result.verdict = "TLE"
    elseif exit_signal and exit_signal ~= 0 then
      result.verdict = "RE"
    elseif exit_code ~= nil and exit_code ~= 0 then
      result.verdict = "RE"
    elseif util.outputs_equal(result.stdout, expected) then
      result.verdict = "AC"
    else
      result.verdict = "WA"
    end

    util.attach_re_cause(result)

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

  local spawn_opts = {
    args = args,
    cwd = vim.fn.fnamemodify(ctx.src_path, ":h"),
    stdio = { stdin, stdout, stderr },
  }
  if time_wrap then
    spawn_opts.detached = true
  end
  local spawn_pid
  handle, spawn_pid = uv.spawn(exec, spawn_opts, function(code, signal)
    exited = true
    exit_code = code
    exit_signal = signal
    if starting_time then
      elapsed_ms = uv.now() - starting_time
    end
    stop_timers()
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

    local peak_closed = false
    local function after_peak()
      close_timer(win_give_up)
      win_give_up = nil
      if not peak_closed then
        peak_closed = true
        if handle and not handle:is_closing() then
          handle:close()
        end
      end
      finish()
    end

    if mem_mode == "win_peak" and pid and not user_cancelled then
      win_peak_pending = true
      local c = win_peak_working_set_kb(pid, function(kb)
        win_peak_pending = false
        if kb then
          note_rss(kb)
        end
        after_peak()
      end)
      if c then
        win_ps_cancels[#win_ps_cancels + 1] = c
      end
      win_give_up = uv.new_timer()
      if win_give_up then
        win_give_up:start(4000, 0, function()
          close_timer(win_give_up)
          win_give_up = nil
          win_peak_pending = false
          win_watch_done = true
          after_peak()
        end)
      end
      return
    end
    if mem_mode == "procfs" and pid then
      note_rss(rss_from_procfs(pid))
    end
    after_peak()
  end)

  if not handle then
    stdin:close()
    stdout:close()
    stderr:close()
    on_done(util.attach_re_cause({
      verdict = "RE",
      stdout = "",
      stderr = "failed to spawn: " .. tostring(exec),
      time_ms = 0,
      code = -1,
    }))
    return
  end

  pid = handle.pid or spawn_pid
  if type(pid) ~= "number" and handle.get_pid then
    pid = handle:get_pid()
  end

  if mem_mode == "win_peak" and type(pid) == "number" then
    win_watch_done = false
    local c = win_watch_peak_kb(pid, function(kb)
      win_watch_done = true
      if kb then
        note_rss(kb)
      end
      finish()
    end)
    if c then
      win_ps_cancels[#win_ps_cancels + 1] = c
    else
      win_watch_done = true
    end
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
    tle_timer = assert(uv.new_timer())
    tle_timer:start(time_limit_ms, 0, function()
      kill_run()
    end)
  end

  if mem_mode == "procfs" then
    sample_rss()
    if not exited then
      mem_timer = assert(uv.new_timer())
      mem_timer:start(20, 20, sample_rss)
    end
  end

  -- Start the clock after spawn/stdio setup, matching CompetiTest.
  starting_time = uv.now()

  return function()
    if finished or user_cancelled then
      return
    end
    user_cancelled = true
    stop_timers()
    cancel_win_ps()
    if time_wrap then
      kill_group()
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
  local job = { cancelled = false, compiling = false }
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
      local cfg = config.options
      local tl = problem.timeLimit or cfg.default_time_limit
      local ml = problem.memoryLimit or cfg.default_memory_limit
      job.kill_current = M.run_one(src_path, ft, tc.input, tc.output, tl, ml, function(result)
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

  job.compile_obj = M.compile(src_path, ft, function(ok, stderr)
    job.compile_obj = nil
    job.compiling = false
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

  -- Only async compiles expose a SystemObj; sync no-op/failure already finished above.
  if job.compile_obj then
    job.compiling = true
    if hooks.on_compile_start then
      hooks.on_compile_start()
    end
  end
end

return M
