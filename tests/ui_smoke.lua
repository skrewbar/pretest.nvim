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

-- Delete confirmation: answer with `confirm_answer` (1 = Yes, 2 = No).
local confirm_answer = 1
vim.fn.confirm = function()
  return confirm_answer
end

-- Harness ------------------------------------------------------------------

local failures = 0

-- print() output gets joined onto one line once nvim_feedkeys has run.
local function out(line)
  io.stdout:write(line, "\n")
end

local function check(name, cond, detail)
  if cond then
    out("  ok   " .. name)
  else
    failures = failures + 1
    out("  FAIL " .. name .. (detail and (": " .. detail) or ""))
  end
end

local function check_eq(name, got, want)
  local same = vim.deep_equal(got, want)
  check(name, same, not same and ("got " .. vim.inspect(got) .. "\n       want " .. vim.inspect(want)) or nil)
end

local function case(name, fn)
  out(name)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    failures = failures + 1
    out("  ERROR " .. tostring(err))
  end
  compiling = false
  hooks = nil
  confirm_answer = 1
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
  -- WinResized forces a full header rebuild without touching run state.
  vim.api.nvim_exec_autocmds("WinResized", {})
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
  check("nothing after the cases", #l == 7, tostring(#l))
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

case("delete asks for confirmation", function()
  local s = open_source(THREE)
  confirm_answer = 2
  ui.delete_testcase(2)
  check("No keeps the case", #s.problem.tests == 3)
  confirm_answer = 1
  ui.delete_testcase(2)
  check("Yes deletes it", #s.problem.tests == 2 and s.problem.tests[2].input == "6")
end)

---Buffer-local normal-mode lhs set of `buf`.
local function buf_maps(buf)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    out[m.lhs] = m.desc or true
  end
  return out
end

case("UI keys follow their scope", function()
  local s = open_source(THREE)
  local header, input, output = buf_maps(s.bufs.header), buf_maps(s.bufs.input), buf_maps(s.bufs.output)
  check("header has a / d", header["a"] and header["d"])
  check("Input has no a / d", not input["a"] and not input["d"])
  check("Output has no a / d", not output["a"] and not output["d"])
  check("s / ? everywhere", input["s"] and input["?"] and output["s"] and header["?"])
  check("desc set", header["a"] == "Add testcase", tostring(header["a"]))
  check("<C-a> everywhere", header["<C-A>"] and input["<C-A>"] and output["<C-A>"])
  local insert_maps = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(s.bufs.expected, "i")) do
    insert_maps[m.lhs] = true
  end
  check("<C-a> in Insert mode", insert_maps["<C-A>"])
end)

case("readonly scope skips Input/Expected", function()
  local config = require("pretest.config")
  local saved = config.options.ui_keys.stop
  config.options.ui_keys.stop = { "<C-c>", { "s", scope = "readonly" } }
  local ok, err = pcall(function()
    local s = open_source(THREE)
    check("Input has no s", not buf_maps(s.bufs.input)["s"])
    check("Expected has no s", not buf_maps(s.bufs.expected)["s"])
    check("Output has s", buf_maps(s.bufs.output)["s"] ~= nil)
    check("Input keeps <C-c>", buf_maps(s.bufs.input)["<C-C>"] ~= nil)
  end)
  config.options.ui_keys.stop = saved
  if not ok then
    error(err, 0)
  end
end)

case("empty_line_marker marks empty lines", function()
  local config = require("pretest.config")
  local ns = vim.api.nvim_create_namespace("pretest_empty_eol")
  local function markers(buf)
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      rows[#rows + 1] = { m[2], m[4].virt_text[1][1] }
    end
    return rows
  end
  local saved = config.options.empty_line_marker
  local ok, err = pcall(function()
    local s = open_source({ { "1\n\n2", "a" } })
    check_eq("default marker on row 1", markers(s.bufs.input), { { 1, saved } })
    config.options.empty_line_marker = "⏎"
    s = open_source({ { "1\n\n2", "a" } })
    check_eq("custom marker", markers(s.bufs.input), { { 1, "⏎" } })
    config.options.empty_line_marker = ""
    s = open_source({ { "1\n\n2", "a" } })
    check_eq("empty string hides markers", markers(s.bufs.input), {})
  end)
  config.options.empty_line_marker = saved
  if not ok then
    error(err, 0)
  end
end)

case("header a / dd / {count}d", function()
  local s = open_source(THREE)
  local hwin = vim.fn.win_findbuf(s.bufs.header)[1]
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_feedkeys("a", "x", false)
  check("a adds case 4", #s.problem.tests == 4 and s.index == 4)
  check("cursor moves to Input", vim.api.nvim_get_current_buf() == s.bufs.input)
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_feedkeys("2d", "x", false)
  check("2d deletes case 2", #s.problem.tests == 3 and s.problem.tests[2].input == "6")
  vim.api.nvim_set_current_win(hwin)
  ui.goto_case(1)
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_feedkeys("dd", "x", false)
  check("dd deletes the current case", #s.problem.tests == 2 and s.problem.tests[1].input == "6")
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_feedkeys("dj", "x", false)
  check("d + other key cancels", #s.problem.tests == 2)
end)

case("<C-a> in Expected adds a case and keeps Insert mode", function()
  local s = open_source(THREE)
  local prev = s.index
  vim.api.nvim_set_current_win(vim.fn.win_findbuf(s.bufs.expected)[1])
  -- Keys typed after <C-a> land in the new Input only if Insert mode is kept.
  vim.api.nvim_feedkeys("A9" .. vim.keycode("<C-a>") .. "5" .. vim.keycode("<Esc>"), "x", false)
  check("adds case 4", #s.problem.tests == 4 and s.index == 4)
  check_eq("typed Expected was saved", s.problem.tests[prev].output, THREE[prev][2] .. "9")
  check("cursor moves to Input", vim.api.nvim_get_current_buf() == s.bufs.input)
  check_eq("Insert mode continues in Input", lines(s.bufs.input), { "5" })
end)

case("focus jumps between source and header", function()
  local s = open_source(THREE)
  local src_buf = s.src_bufnr
  ui.close()
  vim.cmd("Pretest") -- bare :Pretest is ui.focus()
  check("opens the UI", ui.is_open())
  check("lands in the header", vim.api.nvim_get_current_buf() == s.bufs.header)
  ui.focus()
  check("sidebar: back to the source", vim.api.nvim_get_current_buf() == src_buf)
  check("UI stays open", ui.is_open())
  ui.focus()
  check("source: to the header", vim.api.nvim_get_current_buf() == s.bufs.header)
  ui.toggle_layout() -- the float opens focused
  ui.focus()
  check("float: closes", not ui.is_open())
end)

case("help float toggles", function()
  open_source(THREE)
  local before = #vim.api.nvim_list_wins()
  ui.help()
  local win = vim.api.nvim_get_current_win()
  check("opens a float", #vim.api.nvim_list_wins() == before + 1 and vim.api.nvim_win_get_config(win).relative ~= "")
  local text = table.concat(lines(vim.api.nvim_win_get_buf(win)), "\n")
  check("lists dd and {count}d", text:find("dd", 1, true) ~= nil and text:find("{count}d", 1, true) ~= nil)
  ui.help()
  check("second call closes it", #vim.api.nvim_list_wins() == before)
  check("UI still open", ui.is_open())
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
out(failures == 0 and "\nall passed" or ("\n" .. failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
