-- Headless smoke tests for lua/pretest/ui.lua (no dependencies).
-- Run from anywhere: nvim --headless -u NONE -i NONE -l tests/ui_smoke.lua
-- The runner is stubbed: tests drive the run hooks directly.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
-- Headless grid stays 80x24 regardless of 'lines'/'columns'; tests assume that.
vim.o.hidden = true

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
-- macOS: /var -> /private/var; buffer names use the resolved path.
tmp = vim.fn.resolve(tmp)

require("pretest").setup({ companion = { listen_on_setup = false } })
local ui = require("pretest.ui")
local runner = require("pretest.runner")
local prob = require("pretest.prob")

-- Runner stub --------------------------------------------------------------

---@type table|nil
local hooks = nil
local compiling = false
runner.run_tests = function(_, _, _, _, _, h)
  hooks = h
end
runner.is_compiling = function()
  return compiling
end
runner.stop = function()
  compiling = false
  return true
end

-- Harness ------------------------------------------------------------------

local failures = 0

local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    failures = failures + 1
    print("  FAIL " .. name .. (detail and (": " .. detail) or ""))
  end
end

local function check_eq(name, got, want)
  local same = vim.deep_equal(got, want)
  check(name, same, not same and ("got " .. vim.inspect(got) .. "\n       want " .. vim.inspect(want)) or nil)
end

local function case(name, fn)
  print(name)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    failures = failures + 1
    print("  ERROR " .. tostring(err))
  end
  compiling = false
  hooks = nil
  pcall(ui.close)
end

local function S()
  return assert(ui.get_session())
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function shown(buf)
  return #vim.fn.win_findbuf(buf) > 0
end

local HEADER_NS = vim.api.nvim_create_namespace("pretest_header")

---Header lines + HEADER_NS extmarks, normalized for comparison.
local function header_snapshot()
  local buf = S().bufs.header
  local marks = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, HEADER_NS, 0, -1, { details = true })) do
    local d = m[4]
    marks[#marks + 1] =
      string.format("%d:%d-%d:%d:%s", m[2], m[3], d.end_row or -1, d.end_col or -1, d.hl_group or "")
  end
  table.sort(marks)
  return { lines = lines(buf), marks = marks }
end

---Assert the (possibly patched) header equals a full header render.
local function check_header_full(name)
  local before = header_snapshot()
  -- Two hint toggles force a full header rebuild without touching run state.
  ui.toggle_hints()
  ui.toggle_hints()
  check_eq(name, before, header_snapshot())
end

---Count window geometry calls made while running `fn`.
local function count_layout_calls(fn)
  local api = vim.api
  local cfg, height, open = api.nvim_win_set_config, api.nvim_win_set_height, api.nvim_open_win
  local n = 0
  api.nvim_win_set_config = function(...)
    n = n + 1
    return cfg(...)
  end
  api.nvim_win_set_height = function(...)
    n = n + 1
    return height(...)
  end
  api.nvim_open_win = function(...)
    n = n + 1
    return open(...)
  end
  local ok, err = pcall(fn)
  api.nvim_win_set_config, api.nvim_win_set_height, api.nvim_open_win = cfg, height, open
  if not ok then
    error(err, 0)
  end
  return n
end

local seq = 0

---Create a fresh source with `tests`, open it, and show the UI in `mode`.
---@param tests { [1]: string, [2]: string }[]
---@param mode "sidebar"|"float"|nil
local function open_source(tests, mode)
  pcall(ui.close)
  seq = seq + 1
  local path = tmp .. "/s" .. seq .. ".cpp"
  vim.fn.writefile({ "int main() {}" }, path)
  local problem, ppath = prob.load_or_create(path)
  problem.tests = {}
  for i, tc in ipairs(tests) do
    problem.tests[i] = { id = i, input = tc[1], output = tc[2] }
  end
  prob.save(problem, ppath)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  vim.bo.filetype = "cpp"
  ui.show()
  mode = mode or "sidebar"
  if S().ui_mode ~= mode then
    ui.toggle_layout()
  end
  return S()
end

local THREE = { { "1 2", "3" }, { "4 5", "9" }, { "6", "6" } }

local function AC(out)
  return { verdict = "AC", stdout = out or "3", stderr = "", time_ms = 1 }
end
local function WA()
  return { verdict = "WA", stdout = "x", stderr = "", time_ms = 2 }
end
local function RE()
  return {
    verdict = "RE",
    stdout = "",
    stderr = "boom\nline2",
    time_ms = 3,
    reason = "SIGSEGV",
    reason_detail = "segfault",
  }
end

---@param buf integer
---@return string|nil
local function hl_on_row(buf, row, hl)
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, HEADER_NS, { row, 0 }, { row, -1 }, { details = true })) do
    if m[4].hl_group == hl then
      return hl
    end
  end
  return nil
end

-- Tests --------------------------------------------------------------------

case("header rows", function()
  local s = open_source(THREE)
  local l = lines(s.bufs.header)
  check("summary row", l[4] == "Testcases 0/3", l[4])
  check("current marker on case 1", l[5]:find("[1]", 1, true) ~= nil, l[5])
  check("case 2 unmarked", l[6]:find("[", 1, true) == nil, l[6])
  check("hint block follows cases", l[8] == "", l[8])
end)

case("case done updates its row and summary", function()
  local s = open_source(THREE)
  ui.run({ 1, 2, 3 }, false)
  hooks.on_case_start(2)
  hooks.on_case_done(2, WA())
  hooks.on_case_done(1, AC())
  local l = lines(s.bufs.header)
  check("case 2 shows WA", l[6]:find("WA", 1, true) ~= nil, l[6])
  check("case 2 WA highlight", hl_on_row(s.bufs.header, 5, "PretestWA") ~= nil)
  check("summary counts AC", l[4] == "Testcases 1/3", l[4])
end)

for _, mode in ipairs({ "sidebar", "float" }) do
  case("RE/Stderr windows follow current verdict (" .. mode .. ")", function()
    local s = open_source(THREE, mode)
    ui.run({ 1 }, false)
    hooks.on_case_done(1, RE())
    check("RE shown", shown(s.bufs.re))
    check("Stderr shown", shown(s.bufs.stderr))
    check_eq("RE body", lines(s.bufs.re), { "segfault" })
    check_eq("Stderr body", lines(s.bufs.stderr), { "boom", "line2" })
    ui.run({ 1 }, false)
    hooks.on_case_done(1, AC())
    check("RE hidden", not shown(s.bufs.re))
    check("Stderr hidden", not shown(s.bufs.stderr))
    check_eq("Output body", lines(s.bufs.output), { "3" })
  end)
end

case("next_case loads Input/Expected", function()
  local s = open_source(THREE)
  ui.next_case()
  check_eq("input", lines(s.bufs.input), { "4 5" })
  check_eq("expected", lines(s.bufs.expected), { "9" })
  check("marker moved", lines(s.bufs.header)[6]:find("[2]", 1, true) ~= nil)
  check_header_full("header matches full render")
end)

case("closed float UI stays closed when the current case ends RE", function()
  local s = open_source(THREE, "float")
  ui.run({ 1 }, false)
  ui.close()
  local before = #vim.api.nvim_list_wins()
  hooks.on_case_done(1, RE())
  check("no window opened", #vim.api.nvim_list_wins() == before)
  check("RE not shown", not shown(s.bufs.re))
  check("result kept", s.results[1] and s.results[1].verdict == "RE")
  ui.show()
  check("RE shown after reopen", shown(s.bufs.re))
end)

-- Row patches must match a full header render.
case("patched header matches full render through a run", function()
  local s = open_source(THREE)
  ui.run({ 1, 2, 3 }, true)
  compiling = true
  hooks.on_compile_start()
  check("summary shows Compiling", lines(s.bufs.header)[4]:find("Compiling", 1, true) ~= nil)
  check_header_full("compiling")
  compiling = false
  hooks.on_compile_done(true, "")
  check("Compiling cleared", lines(s.bufs.header)[4] == "Testcases 0/3", lines(s.bufs.header)[4])
  check_header_full("compile done")
  hooks.on_case_start(1)
  check_header_full("case 1 running")
  hooks.on_case_done(1, AC())
  hooks.on_case_start(2)
  hooks.on_case_done(2, WA())
  hooks.on_case_start(3)
  check_header_full("case 3 running")
  hooks.on_case_done(3, { verdict = "MLE", stdout = "", stderr = "", time_ms = 4, reason = "300MB" })
  hooks.on_all_done(false)
  check("MLE reason shown", lines(s.bufs.header)[7]:find("300MB", 1, true) ~= nil)
  check_header_full("all done")
end)

case("compile error patches rows and shows compile stderr", function()
  local s = open_source(THREE)
  ui.run({ 1, 2 }, true)
  hooks.on_compile_done(false, "main.cpp:1: error")
  local ce = { verdict = "CE", stdout = "", stderr = "", time_ms = 0, code = 1 }
  hooks.on_case_done(1, ce)
  hooks.on_case_done(2, ce)
  hooks.on_all_done(false)
  check("case 1 CE", lines(s.bufs.header)[5]:find("CE", 1, true) ~= nil)
  check_eq("Stderr shows compile error", lines(s.bufs.stderr), { "main.cpp:1: error" })
  check("Stderr shown", shown(s.bufs.stderr))
  check_header_full("after CE")
  -- New run clears compile stderr even though case 1 is not rerun.
  ui.run({ 2 }, false)
  check("Stderr hidden after rerun clears compile stderr", not shown(s.bufs.stderr))
end)

case("stop marks running rows and compile phase", function()
  local s = open_source(THREE)
  ui.run({ 1, 2 }, false)
  hooks.on_case_start(1)
  ui.stop()
  check("case 1 Stopped", lines(s.bufs.header)[5]:find("Stopped", 1, true) ~= nil, lines(s.bufs.header)[5])
  check_header_full("after stop")
  ui.run({ 1 }, true)
  compiling = true
  hooks.on_compile_start()
  ui.stop()
  check("summary Stopped", lines(s.bufs.header)[4]:find("Stopped", 1, true) ~= nil, lines(s.bufs.header)[4])
  check_header_full("after compile stop")
end)

case("run hooks keep unsaved Input edits, cursor and undo", function()
  local s = open_source(THREE)
  ui.run({ 1, 2, 3 }, false)
  local win = vim.fn.win_findbuf(s.bufs.input)[1]
  vim.api.nvim_buf_set_lines(s.bufs.input, 0, -1, false, { "edited", "more" })
  vim.api.nvim_win_set_cursor(win, { 2, 2 })
  local tick = vim.b[s.bufs.input].changedtick
  hooks.on_case_start(2)
  hooks.on_case_done(2, WA())
  hooks.on_case_start(1)
  hooks.on_case_done(1, RE())
  hooks.on_all_done(false)
  check_eq("Input text kept", lines(s.bufs.input), { "edited", "more" })
  check("Input changedtick kept", vim.b[s.bufs.input].changedtick == tick)
  check_eq("cursor kept", vim.api.nvim_win_get_cursor(win), { 2, 2 })
  check("RE shown for current case", shown(s.bufs.re))
end)

for _, mode in ipairs({ "sidebar", "float" }) do
  case("geometry untouched unless the visible sections change (" .. mode .. ")", function()
    local s = open_source(THREE, mode)
    ui.run({ 1, 2, 3 }, false)
    local n = count_layout_calls(function()
      hooks.on_case_start(2)
      hooks.on_case_done(2, WA())
    end)
    check("other case: 0 window calls", n == 0, tostring(n))
    hooks.on_case_start(1)
    hooks.on_case_done(1, AC())
    n = count_layout_calls(function()
      ui.run({ 1 }, false)
      hooks.on_case_start(1)
      hooks.on_case_done(1, AC())
    end)
    check("AC -> AC on current case: 0 window calls", n == 0, tostring(n))
    n = count_layout_calls(function()
      ui.run({ 1 }, false)
      hooks.on_case_done(1, RE())
    end)
    check("current case RE re-lays out", n > 0 and shown(s.bufs.re), tostring(n))
  end)
end

case("navigation patches rows and reloads bodies", function()
  local s = open_source(THREE, "float")
  ui.run({ 1, 2, 3 }, false)
  hooks.on_case_done(1, AC())
  hooks.on_case_done(2, AC("9"))
  hooks.on_case_done(3, RE())
  local n = count_layout_calls(function()
    ui.next_case()
  end)
  check("AC -> AC move: 0 window calls", n == 0, tostring(n))
  check_eq("Output of case 2", lines(s.bufs.output), { "9" })
  check_header_full("after next_case")
  n = count_layout_calls(function()
    ui.next_case()
  end)
  check("move to RE case re-lays out", n > 0 and shown(s.bufs.re), tostring(n))
  ui.prev_case()
  ui.prev_case()
  ui.prev_case()
  check("prev_case wraps to 3", s.index == 3)
  check_eq("Input of case 3", lines(s.bufs.input), { "6" })
  check_header_full("after prev_case wrap")
  ui.goto_case(1)
  check("goto_case 1", s.index == 1 and lines(s.bufs.header)[5]:find("[1]", 1, true) ~= nil)
  check_header_full("after goto_case")
end)

case("header cursor selects a case once", function()
  local s = open_source(THREE)
  local hwin = vim.fn.win_findbuf(s.bufs.header)[1]
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_win_set_cursor(hwin, { 7, 0 }) -- case 3
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.bufs.header })
  check("index 3", s.index == 3)
  check_eq("Input of case 3", lines(s.bufs.input), { "6" })
  local tick = vim.b[s.bufs.input].changedtick
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.bufs.header })
  check("second CursorMoved is a no-op", s.index == 3 and vim.b[s.bufs.input].changedtick == tick)
  check_eq("cursor stays on the case row", vim.api.nvim_win_get_cursor(hwin), { 7, 0 })
  check_header_full("after header select")
end)

case("toggle_hints rebuilds header and heights", function()
  local s = open_source(THREE)
  local function heights()
    local out = {}
    for key, buf in pairs(s.bufs) do
      local win = vim.fn.win_findbuf(buf)[1]
      out[key] = win and vim.api.nvim_win_get_height(win) or 0
    end
    return out
  end
  local with_hints = #lines(s.bufs.header)
  ui.toggle_hints()
  check("hints removed", #lines(s.bufs.header) == 7, tostring(#lines(s.bufs.header)))
  local toggled = heights()
  ui.close()
  ui.show()
  check_eq("heights match a fresh open (hints off)", toggled, heights())
  ui.toggle_hints()
  check("hints restored", #lines(s.bufs.header) == with_hints)
  toggled = heights()
  ui.close()
  ui.show()
  check_eq("heights match a fresh open (hints on)", toggled, heights())
  check_header_full("after toggles")
end)

case("add/delete testcase rebuild header rows", function()
  local s = open_source(THREE)
  ui.add_testcase()
  local l = lines(s.bufs.header)
  check("4 case rows", l[8] ~= nil and l[8]:find("[4]", 1, true) ~= nil, l[8])
  check_eq("new case Input empty", lines(s.bufs.input), { "" })
  check_header_full("after add")
  ui.delete_testcase(4)
  check("back to 3 cases", s.index == 3 and #s.problem.tests == 3)
  check_eq("Input of case 3", lines(s.bufs.input), { "6" })
  check_header_full("after delete")
end)

case("delete with UI closed keeps edit buffers in sync", function()
  local s = open_source(THREE)
  ui.close()
  ui.delete_testcase(1)
  check_eq("Input is new case 1", lines(s.bufs.input), { "4 5" })
  ui.run({ 1 }, false) -- flushes edit buffers into tests[1]
  check("tests[1] not overwritten", s.problem.tests[1].input == "4 5", s.problem.tests[1].input)
  check("tests[2] intact", s.problem.tests[2].input == "6", s.problem.tests[2].input)
end)

case("edit_name / edit_limits patch their rows", function()
  local s = open_source(THREE)
  local orig = vim.ui.input
  local answers = { "Renamed", "1500", "256" }
  vim.ui.input = function(_, cb)
    cb(table.remove(answers, 1))
  end
  local ok, err = pcall(function()
    local tick = vim.b[s.bufs.input].changedtick
    ui.edit_name()
    check("name row", lines(s.bufs.header)[1] == "Renamed")
    ui.edit_limits()
    check("limits row", lines(s.bufs.header)[2] == "TL 1500ms │ ML 256MB", lines(s.bufs.header)[2])
    check("Input untouched", vim.b[s.bufs.input].changedtick == tick)
    check_header_full("after edits")
  end)
  vim.ui.input = orig
  if not ok then
    error(err, 0)
  end
end)

case("WinResized redraws header only", function()
  local s = open_source(THREE)
  local hwin = vim.fn.win_findbuf(s.bufs.header)[1]
  local tick = vim.b[s.bufs.input].changedtick
  vim.api.nvim_win_set_width(hwin, 52)
  vim.api.nvim_exec_autocmds("WinResized", {})
  local width = vim.api.nvim_win_get_width(hwin)
  check("separator follows width", vim.fn.strchars(lines(s.bufs.header)[3]) == width, width .. "")
  check("Input untouched", vim.b[s.bufs.input].changedtick == tick)
  check_header_full("after resize")
end)

-- UI windows keep their buffers / source window lifecycle -------------------

---Let vim.schedule callbacks (BufEnter / WinClosed follow-ups) run.
local function settle()
  vim.wait(20, function()
    return false
  end)
end

---Load another source file as a hidden listed buffer.
---@return integer buf, string path
local function extra_source()
  seq = seq + 1
  local path = tmp .. "/s" .. seq .. ".cpp"
  vim.fn.writefile({ "int main() {}" }, path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.bo[buf].filetype = "cpp"
  return buf, path
end

---First window of the current tab showing `buf`.
local function win_of(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

local function reset_windows()
  pcall(ui.close)
  vim.cmd("silent! tabonly")
  vim.cmd("silent! only")
  settle()
end

---Open `buf` in a new window above `win` and return to `win`.
local function split_above(win, buf)
  vim.api.nvim_set_current_win(win)
  vim.cmd("aboveleft split")
  local new = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new, buf)
  vim.api.nvim_set_current_win(win)
  settle()
  return new
end

case("buffer opened in a sidebar window moves to the source window", function()
  reset_windows()
  local s = open_source(THREE)
  local src_win = win_of(s.src_bufnr)
  vim.wo[src_win].number = true
  local other, other_path = extra_source()
  local input_win = win_of(s.bufs.input)
  vim.api.nvim_set_current_win(input_win)
  vim.api.nvim_set_current_buf(other)
  check_eq("Input window keeps Input", vim.api.nvim_win_get_buf(input_win), s.bufs.input)
  check_eq("source window shows the new buffer", vim.api.nvim_win_get_buf(src_win), other)
  check_eq("focus moves to the source window", vim.api.nvim_get_current_win(), src_win)
  check("source window keeps its options", vim.wo[src_win].number and not vim.wo[src_win].list)
  check_eq("Input winbar kept", vim.api.nvim_get_option_value("winbar", { win = input_win, scope = "local" }), "Input")
  settle()
  check("UI still open", ui.is_open())
  check_eq("UI follows the new source", S().src_path, other_path)
end)

case("source buffer opened in the header window goes back to the source window", function()
  reset_windows()
  local s = open_source(THREE)
  local src_win = win_of(s.src_bufnr)
  local header_win = win_of(s.bufs.header)
  local index = S().index
  vim.api.nvim_set_current_win(header_win)
  vim.api.nvim_set_current_buf(s.src_bufnr)
  check_eq("header window keeps the header", vim.api.nvim_win_get_buf(header_win), s.bufs.header)
  check_eq("focus moves to the source window", vim.api.nvim_get_current_win(), src_win)
  settle()
  check("UI still open", ui.is_open())
  check_eq("case selection unchanged", S().index, index)
end)

case("buffer opened in a float window moves to the editing window", function()
  reset_windows()
  local s = open_source(THREE, "float")
  local src_win = win_of(s.src_bufnr)
  local other, other_path = extra_source()
  local input_win = win_of(s.bufs.input)
  vim.api.nvim_set_current_win(input_win)
  vim.api.nvim_set_current_buf(other)
  check_eq("Input float keeps Input", vim.api.nvim_win_get_buf(input_win), s.bufs.input)
  check_eq("editing window shows the new buffer", vim.api.nvim_win_get_buf(src_win), other)
  check_eq("focus leaves the float", vim.api.nvim_get_current_win(), src_win)
  settle()
  check_eq("UI follows the new source", S().src_path, other_path)
end)

case("closing one of two source windows keeps the UI", function()
  reset_windows()
  local s = open_source(THREE)
  local src = s.src_bufnr
  local src_win = win_of(src)
  split_above(src_win, src)
  vim.api.nvim_set_current_win(win_of(s.bufs.input))
  vim.api.nvim_win_close(src_win, false)
  settle()
  check("UI still open", ui.is_open())
  check_eq("same source", S().src_bufnr, src)
end)

case("closing the source window hands the UI to the focused source", function()
  reset_windows()
  local s = open_source(THREE)
  local a_win = win_of(s.src_bufnr)
  local other, other_path = extra_source()
  local b_win = split_above(a_win, other)
  vim.cmd("close")
  check_eq("focus lands on the other source", vim.api.nvim_get_current_win(), b_win)
  settle()
  check("UI still open", ui.is_open())
  check_eq("UI follows the other source", S().src_path, other_path)
end)

case("closing the source window from the UI switches to a visible source", function()
  reset_windows()
  local s = open_source(THREE)
  local a_win = win_of(s.src_bufnr)
  local other, other_path = extra_source()
  split_above(a_win, other)
  local input_win = win_of(s.bufs.input)
  vim.api.nvim_set_current_win(input_win)
  vim.api.nvim_win_close(a_win, false)
  settle()
  check("UI still open", ui.is_open())
  check_eq("UI follows the other source", S().src_path, other_path)
  check_eq("focus stays in Input", vim.api.nvim_get_current_win(), input_win)
end)

case("closing the last source window from the UI closes the UI", function()
  reset_windows()
  local s = open_source(THREE)
  local a_win = win_of(s.src_bufnr)
  local scratch = vim.api.nvim_create_buf(false, true)
  split_above(a_win, scratch)
  vim.api.nvim_set_current_win(win_of(s.bufs.input))
  vim.api.nvim_win_close(a_win, false)
  settle()
  check("UI closed", not ui.is_open())
end)

case(":quit on the last source window closes the UI with its tab", function()
  reset_windows()
  vim.cmd("tabnew")
  local s = open_source(THREE)
  vim.api.nvim_set_current_win(win_of(s.src_bufnr))
  vim.cmd("quit")
  settle()
  check("UI closed", not ui.is_open())
  check_eq("tab closed", #vim.api.nvim_list_tabpages(), 1)
end)

case(":close on the last source window leaves one empty window", function()
  reset_windows()
  local s = open_source(THREE)
  local global_number = vim.go.number
  vim.go.number = true
  vim.api.nvim_set_current_win(win_of(s.src_bufnr))
  vim.cmd("close")
  settle()
  check("UI closed", not ui.is_open())
  local wins = vim.api.nvim_tabpage_list_wins(0)
  check_eq("one window left", #wins, 1)
  local buf = vim.api.nvim_win_get_buf(wins[1])
  check("empty editing buffer", vim.api.nvim_buf_get_name(buf) == "" and vim.bo[buf].buftype == "")
  check("UI window options reset", vim.wo[wins[1]].number and not vim.wo[wins[1]].winfixwidth)
  check_eq("winbar cleared", vim.api.nvim_get_option_value("winbar", { win = wins[1], scope = "local" }), "")
  vim.go.number = global_number
end)

case("<C-w>T on the source window leaves an empty window behind", function()
  reset_windows()
  local s = open_source(THREE)
  local src = s.src_bufnr
  local ui_tab = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(win_of(src))
  vim.cmd("wincmd T")
  settle()
  check("UI closed", not ui.is_open())
  local old = vim.api.nvim_tabpage_list_wins(ui_tab)
  check_eq("old tab keeps one window", #old, 1)
  check_eq("old tab window is empty", vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(old[1])), "")
  check_eq("new tab shows the source", vim.api.nvim_get_current_buf(), src)
end)

reset_windows()

-- Done ---------------------------------------------------------------------

vim.fn.delete(tmp, "rf")
print(failures == 0 and "\nall passed" or ("\n" .. failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
