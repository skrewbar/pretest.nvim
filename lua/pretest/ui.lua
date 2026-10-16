local config = require("pretest.config")
local prob = require("pretest.prob")
local runner = require("pretest.runner")
local util = require("pretest.util")

local M = {}

---@class pretest.Session
---@field src_bufnr integer
---@field src_path string
---@field filetype string
---@field problem pretest.Problem
---@field prob_path string|nil
---@field index integer
---@field results table<integer, pretest.CaseResult>
---@field ui_mode "sidebar"|"float"
---@field winids integer[]
---@field win_bufs table<integer, integer> # UI window → the UI buffer it must keep showing
---@field bufs { header: integer, input: integer, expected: integer, output: integer, re: integer, stderr: integer }
---@field applying boolean
---@field closing boolean
---@field compile_stderr string
---@field compile_status "stopped"|nil
---@field layout_key string|nil # last applied window layout; nil forces a re-layout
---@field header_n integer|nil # testcase count at the last full header render
---@field header_rows integer|nil # header line count at the last full header render
---@field drawn_index integer|nil # case index drawn with the `[n]` marker

---@type pretest.Session|nil
local session = nil

---Per-source results kept while the UI is showing another file.
---@type table<string, { results: table<integer, pretest.CaseResult>, index: integer, compile_stderr: string }>
local parked = {}

---Assigned after helpers exist; autocmds in setup() close over these upvalues.
local follow_visible_source
local guard_ui_win
local before_quit
local after_win_closed

---Remembers last chosen UI mode for this Neovim session (falls back to config.ui).
---@type "sidebar"|"float"|nil
local preferred_ui = nil

local HEADER_NS = vim.api.nvim_create_namespace("pretest_header")
local EMPTY_EOL_NS = vim.api.nvim_create_namespace("pretest_empty_eol")
local HEADER_HEIGHT_CAP = 36
local highlights_setup = false

---@return "sidebar"|"float"
local function get_preferred_ui()
  if preferred_ui == "sidebar" or preferred_ui == "float" then
    return preferred_ui
  end
  local ui = config.options.ui
  if ui == "float" then
    return "float"
  end
  return "sidebar"
end

---@return integer
local function resolved_sidebar_width()
  local cfg = config.options
  return util.resolve_size(
    cfg.sidebar_width,
    cfg.sidebar_min_width,
    cfg.sidebar_max_width,
    vim.o.columns,
    40
  )
end

---@return integer
local function resolved_float_width()
  local cfg = config.options
  return util.resolve_size(
    cfg.float_width,
    cfg.float_min_width,
    cfg.float_max_width,
    vim.o.columns,
    0.6
  )
end

---@return integer
local function resolved_float_height()
  local cfg = config.options
  return util.resolve_size(
    cfg.float_height,
    cfg.float_min_height,
    cfg.float_max_height,
    vim.o.lines,
    0.8
  )
end

---@param win integer
---@param text string
local function set_winbar(win, text)
  -- scope=local: winbar is global-or-local; :set would leak into new floats.
  pcall(vim.api.nvim_set_option_value, "winbar", text, { win = win, scope = "local" })
end

---@param win integer
---@param kind "header"|"body"
local function configure_win(win, kind)
  local body = kind == "body"
  -- [0] = :setlocal; plain vim.wo[win] also rewrites the global values (:set).
  local wo = vim.wo[win][0]
  wo.number = false
  wo.relativenumber = false
  wo.wrap = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.list = body
  if body then
    wo.listchars = "tab:>·,trail:-"
  end
  wo.cursorline = false
  if session and session.ui_mode == "sidebar" then
    wo.winfixwidth = true
  end
  -- Sidebar last-used winbar is remembered on the buffer; floats use border titles.
  if session and session.ui_mode == "float" then
    set_winbar(win, "")
  end
end

---Window options configure_win / set_winbar change.
local UI_WIN_OPTS = {
  "number",
  "relativenumber",
  "wrap",
  "signcolumn",
  "foldcolumn",
  "list",
  "listchars",
  "cursorline",
  "winfixwidth",
  "winbar",
}

---@param win integer
---@return table<string, any>
local function get_win_opts(win)
  local opts = {}
  for _, name in ipairs(UI_WIN_OPTS) do
    opts[name] = vim.api.nvim_get_option_value(name, { win = win, scope = "local" })
  end
  return opts
end

---@param win integer
---@param opts table<string, any>
local function set_win_opts(win, opts)
  for name, value in pairs(opts) do
    pcall(vim.api.nvim_set_option_value, name, value, { win = win, scope = "local" })
  end
end

---Undo configure_win on a window that stops being part of the UI.
---@param win integer
local function reset_win_opts(win)
  local opts = {}
  for _, name in ipairs(UI_WIN_OPTS) do
    opts[name] = vim.api.nvim_get_option_value(name, { scope = "global" })
  end
  set_win_opts(win, opts)
end

---Mark completely empty lines with an eol indicator (listchars eol would mark every line).
---@param buf integer
local function apply_empty_eol_marks(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, EMPTY_EOL_NS, 0, -1)
  local marker = config.options.empty_line_marker
  if marker == "" then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == "" then
      -- overlay at col 0: eol virt_text on empty lines sits one column in and looks indented.
      vim.api.nvim_buf_set_extmark(buf, EMPTY_EOL_NS, i - 1, 0, {
        virt_text = { { marker, "NonText" } },
        virt_text_pos = "overlay",
      })
    end
  end
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Programmatic updates must not leave buffers "modified", or :qa prompts to save.
  vim.bo[buf].modified = false
end

---Fill Input/Expected from the current testcase so flush_edits can always read them.
local function load_edit_bufs()
  if not session then
    return
  end
  local n = #session.problem.tests
  local tc = session.problem.tests[session.index]
  set_lines(session.bufs.input, tc and util.split_lines(tc.input) or { "" })
  vim.bo[session.bufs.input].modifiable = n > 0
  apply_empty_eol_marks(session.bufs.input)

  set_lines(session.bufs.expected, tc and util.split_lines(tc.output) or { "" })
  vim.bo[session.bufs.expected].modifiable = n > 0
  apply_empty_eol_marks(session.bufs.expected)
end

---@param name string
---@param modifiable boolean
---@param buftype string|nil # default: editable → acwrite, readonly → nofile
local function make_buf(name, modifiable, buftype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name .. "#" .. buf)
  vim.bo[buf].buftype = buftype or (modifiable and "acwrite" or "nofile")
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "pretest"
  vim.bo[buf].modifiable = modifiable
  vim.bo[buf].modified = false
  return buf
end

local function clear_ui_modified()
  if not session or not session.bufs then
    return
  end
  for _, buf in pairs(session.bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modified = false
    end
  end
end

---@param bufnr integer
---@return boolean
local function is_ui_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].filetype == "pretest" then
    return true
  end
  if session and session.bufs then
    for _, b in pairs(session.bufs) do
      if b == bufnr then
        return true
      end
    end
  end
  return false
end

local function apply_highlights()
  local links = {
    PretestAC = "DiagnosticOk",
    PretestWA = "DiagnosticError",
    PretestRE = "DiagnosticError",
    PretestTLE = "DiagnosticWarn",
    PretestMLE = "DiagnosticWarn",
    PretestCE = "DiagnosticError",
    PretestStopped = "DiagnosticWarn",
    PretestRunning = "DiagnosticInfo",
    PretestPending = "Comment",
    PretestCurrent = "Title",
    PretestKey = "Special",
    PretestHint = "Comment",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  -- Separator line: FloatBorder foreground only (no bg — linking FloatBorder
  -- often paints a dark bar across the row).
  local fb = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
  vim.api.nvim_set_hl(0, "PretestSep", {
    fg = fb.fg,
    ctermfg = fb.ctermfg,
    bg = "NONE",
    ctermbg = "NONE",
    default = true,
  })
end

function M.setup()
  if highlights_setup then
    return
  end
  highlights_setup = true
  apply_highlights()
  local group = vim.api.nvim_create_augroup("pretest_ui", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = apply_highlights,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if not session then
        return
      end
      pcall(M.flush_edits)
      clear_ui_modified()
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      vim.schedule(follow_visible_source)
    end,
  })
  -- Synchronous (no schedule) so a buffer opened in a UI window never gets drawn there.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    nested = true,
    callback = function(ev)
      guard_ui_win(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function(ev)
      if not session then
        return
      end
      if not is_ui_buf(vim.api.nvim_get_current_buf()) then
        -- <abuf> is the buffer of the window being quit (also for `:{count}quit`).
        before_quit(ev.buf)
        return
      end
      M.flush_edits()
      clear_ui_modified()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      if not session or session.applying or session.closing then
        return
      end
      local closed = tonumber(ev.match)
      for _, win in ipairs(session.winids) do
        if win == closed then
          M.close()
          return
        end
      end
      if not closed or not M.is_open() or not vim.api.nvim_win_is_valid(closed) then
        return
      end
      -- Floats never hold the source, so closing one cannot change where it is shown.
      if vim.api.nvim_win_get_config(closed).relative ~= "" then
        return
      end
      -- The window is still open here; decide once the layout has settled.
      local tab = vim.api.nvim_win_get_tabpage(closed)
      vim.schedule(function()
        after_win_closed(tab)
      end)
    end,
  })
end

---@class pretest.HeaderLayout
---@field name_row integer
---@field limits_row integer
---@field sep_row integer
---@field cases_label_row integer
---@field cases_start integer
---@field min_height integer
---@field n integer

---@param n integer
---@return pretest.HeaderLayout
local function header_layout(n)
  local name_row = 0
  local limits_row = 1
  local sep_row = 2
  -- name, limits, sep, "Testcases AC/total", then cases
  local cases_label_row = 3
  local cases_start = 4
  -- name + limits + sep + label + cases
  local min_height = math.min(HEADER_HEIGHT_CAP, math.max(4, 4 + n))
  return {
    name_row = name_row,
    limits_row = limits_row,
    sep_row = sep_row,
    cases_label_row = cases_label_row,
    cases_start = cases_start,
    min_height = min_height,
    n = n,
  }
end

---@param n integer
---@return integer
local function header_content_min(n)
  return header_layout(n).min_height
end

local CASES_LABEL = "Testcases "
local COMPILING_LABEL = "Compiling"
local COMPILE_STOPPED_LABEL = "Stopped"

---@return "compiling"|"stopped"|nil
local function compile_phase()
  if not session then
    return nil
  end
  if runner.is_compiling(session.src_path) then
    return "compiling"
  end
  if session.compile_status == "stopped" then
    return "stopped"
  end
  return nil
end

---@return integer ac
---@return integer total
---@return string hl
local function ac_summary()
  local total = (session and session.problem and #session.problem.tests) or 0
  local ac, has_fail, has_running, has_stopped = 0, false, false, false
  if session then
    for i = 1, total do
      local v = session.results[i] and session.results[i].verdict
      if v == "AC" then
        ac = ac + 1
      elseif v == "Running" then
        has_running = true
      elseif v == "Stopped" then
        has_stopped = true
      elseif v and v ~= "Pending" then
        has_fail = true
      end
    end
  end
  local hl
  if total > 0 and ac == total then
    hl = "PretestAC"
  elseif has_fail then
    hl = "PretestWA"
  elseif has_running then
    hl = "PretestRunning"
  elseif has_stopped then
    hl = "PretestStopped"
  else
    hl = "PretestPending"
  end
  return ac, total, hl
end

---@return string|nil
local function compile_phase_suffix()
  local phase = compile_phase()
  if phase == "compiling" then
    return COMPILING_LABEL
  elseif phase == "stopped" then
    return COMPILE_STOPPED_LABEL
  end
  return nil
end

---@return string
local function format_cases_label()
  local ac, total = ac_summary()
  local line = CASES_LABEL .. string.format("%d/%d", ac, total)
  local suffix = compile_phase_suffix()
  if suffix then
    line = line .. "  " .. suffix
  end
  return line
end

---@param verdict string|nil
---@return string|nil
local function verdict_hl(verdict)
  if not verdict or verdict == "Pending" then
    return "PretestPending"
  end
  if verdict == "AC" then
    return "PretestAC"
  elseif verdict == "WA" then
    return "PretestWA"
  elseif verdict == "RE" then
    return "PretestRE"
  elseif verdict == "TLE" then
    return "PretestTLE"
  elseif verdict == "MLE" then
    return "PretestMLE"
  elseif verdict == "CE" then
    return "PretestCE"
  elseif verdict == "Stopped" then
    return "PretestStopped"
  elseif verdict == "Running" then
    return "PretestRunning"
  end
  return "PretestPending"
end

---@param i integer
---@param n integer
---@param idx integer
---@param result pretest.CaseResult|nil
---@return string line
---@return integer num_col
---@return integer num_end
---@return integer|nil verdict_col
---@return integer|nil verdict_end
---@return string|nil hl
local function format_case_line(i, n, idx, result)
  local width = #tostring(math.max(n, 1))
  local digits = tostring(i)
  local pad = width - #digits
  -- Pad outside the brackets so they hug the digits while the units column stays aligned.
  local num, num_col
  if i == idx then
    num = string.rep(" ", pad) .. "[" .. digits .. "]"
    num_col = pad
  else
    num = string.rep(" ", pad + 1) .. digits .. " "
    num_col = 0
  end

  local verdict = result and result.verdict or nil
  local show = verdict and verdict ~= "Pending"
  if not show then
    return num, num_col, #num, nil, nil, verdict_hl(verdict)
  end

  -- Pad so time always starts at the same column, and reason starts at the
  -- same column after a right-aligned time field.
  local VERDICT_WIDTH = 4
  local TIME_WIDTH = 7 -- "1234ms" / "   12ms"; fits up to 99999ms
  local verdict_s = string.format("%-" .. VERDICT_WIDTH .. "s", verdict)
  local time_label = result.time_ms and string.format("%.0fms", result.time_ms) or ""
  local reason_s = ""
  if (verdict == "RE" or verdict == "MLE") and result.reason and result.reason ~= "" then
    reason_s = "  " .. result.reason
  end
  local time_s = ""
  if time_label ~= "" or reason_s ~= "" then
    time_s = string.format("%" .. TIME_WIDTH .. "s", time_label)
  end
  local line = num .. " " .. verdict_s .. time_s .. reason_s
  local vcol = #num + 1
  return line, num_col, #num, vcol, vcol + #verdict, verdict_hl(verdict)
end

---@param buf integer
---@param row integer
---@return string
local function buf_line(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

---@param buf integer
---@param layout pretest.HeaderLayout
local function mark_sep_row(buf, layout)
  local sep_line = buf_line(buf, layout.sep_row)
  if sep_line ~= "" then
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.sep_row, 0, {
      end_col = #sep_line,
      hl_group = "PretestSep",
    })
  end
end

---@param buf integer
---@param layout pretest.HeaderLayout
local function mark_limits_row(buf, layout)
  local limits_line = buf_line(buf, layout.limits_row)
  local bar_col = limits_line:find("│", 1, true)
  if bar_col then
    -- find() returns 1-based byte index of the first byte of │
    local bar_start = bar_col - 1
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.limits_row, bar_start, {
      end_col = bar_start + #"│",
      hl_group = "PretestSep",
    })
  end
end

---@param buf integer
---@param layout pretest.HeaderLayout
local function mark_label_row(buf, layout)
  local label_line = buf_line(buf, layout.cases_label_row)
  if #label_line <= #CASES_LABEL then
    return
  end
  local suffix = compile_phase_suffix()
  local count_end = #label_line
  if suffix then
    local suffix_col = #label_line - #suffix
    count_end = suffix_col - 2 -- two spaces before the suffix
    local suffix_hl = suffix == COMPILING_LABEL and "PretestRunning" or "PretestStopped"
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.cases_label_row, suffix_col, {
      end_col = #label_line,
      hl_group = suffix_hl,
    })
  end
  if count_end > #CASES_LABEL then
    local _, _, summary_hl = ac_summary()
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.cases_label_row, #CASES_LABEL, {
      end_col = count_end,
      hl_group = summary_hl,
    })
  end
end

---@param buf integer
---@param layout pretest.HeaderLayout
---@param i integer
---@param idx integer
local function mark_case_row(buf, layout, i, idx)
  local row = layout.cases_start + i - 1
  local result = session.results[i]
  local line, num_col, num_end, vcol, vend, hl = format_case_line(i, layout.n, idx, result)
  if i == idx then
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, row, num_col, {
      end_col = num_end,
      hl_group = "PretestCurrent",
    })
  end
  if vcol and vend and hl then
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, row, vcol, {
      end_col = vend,
      hl_group = hl,
    })
  elseif hl and (not result or result.verdict == "Pending" or result.verdict == "Running") then
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, row, 0, {
      end_col = #line,
      hl_group = hl,
    })
  end
end

---@param buf integer
---@param layout pretest.HeaderLayout
---@param idx integer
local function apply_header_marks(buf, layout, idx)
  vim.api.nvim_buf_clear_namespace(buf, HEADER_NS, 0, -1)
  mark_sep_row(buf, layout)
  mark_limits_row(buf, layout)
  mark_label_row(buf, layout)
  for i = 1, layout.n do
    mark_case_row(buf, layout, i, idx)
  end
end

function M.get_session()
  return session
end

---Source buffer the current window stands for: the session source while the
---cursor is in a UI window, otherwise the current buffer.
---@return integer|nil # nil in a UI window without a session
function M.current_source_buf()
  local bufnr = vim.api.nvim_get_current_buf()
  if is_ui_buf(bufnr) then
    return session and session.src_bufnr
  end
  return bufnr
end

function M.is_open()
  if not session then
    return false
  end
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) then
      return true
    end
  end
  return false
end

function M.close()
  if not session or session.closing then
    return
  end
  session.closing = true
  M.flush_edits()
  clear_ui_modified()
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  session.winids = {}
  session.win_bufs = {}
  session.layout_key = nil
  session.closing = false
end

function M.flush_edits()
  if not session or not session.problem or #session.problem.tests == 0 then
    return
  end
  local tc = session.problem.tests[session.index]
  if session.bufs.input and vim.api.nvim_buf_is_valid(session.bufs.input) then
    local lines = vim.api.nvim_buf_get_lines(session.bufs.input, 0, -1, false)
    tc.input = util.join_lines(lines)
  end
  if session.bufs.expected and vim.api.nvim_buf_is_valid(session.bufs.expected) then
    local lines = vim.api.nvim_buf_get_lines(session.bufs.expected, 0, -1, false)
    tc.output = util.join_lines(lines)
  end
  prob.save(session.problem, session.prob_path)
end

local function current_result()
  if not session then
    return nil
  end
  return session.results[session.index]
end

local SECTION_KEYS = { "header", "input", "expected", "output" }

---Split `budget` among header/input/expected/output by weights.
---Integer remainder always goes to header (float and sidebar).
---@param budget integer
---@param sec { header?: number, input?: number, expected?: number, output?: number }|nil
---@return integer header, integer input, integer expected, integer output
local function section_heights_from_weights(budget, sec)
  sec = sec or {}
  local weights = {
    header = math.max(0.0001, tonumber(sec.header) or 1),
    input = math.max(0.0001, tonumber(sec.input) or 1),
    expected = math.max(0.0001, tonumber(sec.expected) or 1),
    output = math.max(0.0001, tonumber(sec.output) or 1),
  }
  local mins = { header = 3, input = 3, expected = 3, output = 3 }
  budget = math.max(12, budget)

  local total_w = weights.header + weights.input + weights.expected + weights.output
  ---@type table<string, integer>
  local heights = {}
  local used = 0
  for _, key in ipairs(SECTION_KEYS) do
    if key ~= "header" then
      heights[key] = math.floor(budget * weights[key] / total_w)
      used = used + heights[key]
    end
  end
  heights.header = budget - used

  for _, key in ipairs(SECTION_KEYS) do
    while heights[key] < mins[key] do
      local donor, donor_extra = nil, 0
      for _, other in ipairs(SECTION_KEYS) do
        if other ~= key then
          local extra = heights[other] - mins[other]
          if extra > donor_extra then
            donor_extra = extra
            donor = other
          end
        end
      end
      if not donor then
        break
      end
      heights[donor] = heights[donor] - 1
      heights[key] = heights[key] + 1
    end
  end

  return heights.header, heights.input, heights.expected, heights.output
end

---@param show_re boolean
---@param re_h integer|nil
---@param show_stderr boolean
---@param stderr_h integer|nil
---@return table<string, integer>
local function compute_float_heights(show_re, re_h, show_stderr, stderr_h)
  local cfg = config.options
  local extra_n = (show_re and 1 or 0) + (show_stderr and 1 or 0)
  local n_sections = 4 + extra_n
  local border = 2
  local total_outer = resolved_float_height()
  re_h = show_re and math.max(1, re_h or 2) or 0
  stderr_h = show_stderr and math.max(1, stderr_h or 2) or 0
  local content_budget = math.max(12, total_outer - n_sections * border - re_h - stderr_h)
  local header, input, expected, output = section_heights_from_weights(content_budget, cfg.float_sections)

  return {
    header = header,
    input = input,
    expected = expected,
    output = output,
    re = re_h,
    stderr = stderr_h,
    total_outer = total_outer,
  }
end

---Apply weighted heights to sidebar header + body windows.
---@param extra_h integer|nil RE + Stderr fixed heights
local function apply_sidebar_section_heights(extra_h)
  if not session then
    return
  end
  extra_h = extra_h or 0
  local total = 0
  local wins = {}
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) then
      total = total + vim.api.nvim_win_get_height(win)
      local buf = vim.api.nvim_win_get_buf(win)
      if
        buf == session.bufs.header
        or buf == session.bufs.input
        or buf == session.bufs.expected
        or buf == session.bufs.output
      then
        table.insert(wins, { win = win, buf = buf })
      end
    end
  end
  local remaining = math.max(12, total - extra_h)
  local header_h, input_h, expected_h, output_h =
    section_heights_from_weights(remaining, config.options.sidebar_sections)
  local hmin = header_content_min(#session.problem.tests)
  if header_h < hmin and remaining >= hmin + 9 then
    header_h = hmin
    local body_budget = remaining - header_h
    local sec = config.options.sidebar_sections or {}
    local wi = math.max(0.0001, tonumber(sec.input) or 1)
    local we = math.max(0.0001, tonumber(sec.expected) or 1)
    local wo = math.max(0.0001, tonumber(sec.output) or 1)
    local tw = wi + we + wo
    input_h = math.max(3, math.floor(body_budget * wi / tw + 1e-9))
    expected_h = math.max(3, math.floor(body_budget * we / tw + 1e-9))
    output_h = math.max(3, body_budget - input_h - expected_h)
  end
  local by_buf = {
    [session.bufs.header] = header_h,
    [session.bufs.input] = input_h,
    [session.bufs.expected] = expected_h,
    [session.bufs.output] = output_h,
  }
  for _, item in ipairs(wins) do
    pcall(vim.api.nvim_win_set_height, item.win, by_buf[item.buf])
  end
end

---@param buf integer
---@return integer|nil
local function find_win_for_buf(buf)
  if not session then
    return nil
  end
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return nil
end

---@param win integer|nil
local function sync_header_cursor(win)
  if not session or session.index < 1 then
    return
  end
  win = win or vim.api.nvim_get_current_win()
  if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= session.bufs.header then
    return
  end
  local layout = header_layout(#session.problem.tests)
  local row = layout.cases_start + session.index - 1
  session.applying = true
  pcall(vim.api.nvim_win_set_cursor, win, { row + 1, 0 })
  session.applying = false
end

---@return integer[]
local function section_cycle_order()
  if not session then
    return {}
  end
  local order = {}
  for _, key in ipairs({ "header", "input", "expected", "output", "re", "stderr" }) do
    local win = find_win_for_buf(session.bufs[key])
    if win then
      order[#order + 1] = win
    end
  end
  return order
end

---@param delta integer
local function focus_section(delta)
  local wins = section_cycle_order()
  if #wins == 0 then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  local idx
  for i, win in ipairs(wins) do
    if win == cur then
      idx = i
      break
    end
  end
  local next_idx
  if not idx then
    next_idx = delta > 0 and 1 or #wins
  else
    next_idx = ((idx - 1 + delta) % #wins) + 1
  end
  local target = wins[next_idx]
  pcall(vim.api.nvim_set_current_win, target)
  sync_header_cursor(target)
  if vim.fn.mode():find("i", 1, true) and target and vim.api.nvim_win_is_valid(target) then
    local buf = vim.api.nvim_win_get_buf(target)
    if not vim.bo[buf].modifiable then
      vim.cmd("stopinsert")
    end
  end
end

---@return integer
local function header_sep_width()
  if not session then
    return 20
  end
  local win = find_win_for_buf(session.bufs.header)
  if win then
    return math.max(1, vim.api.nvim_win_get_width(win))
  end
  if session.ui_mode == "float" then
    return resolved_float_width()
  end
  return resolved_sidebar_width()
end

---@return string
local function header_sep_line()
  return string.rep("─", header_sep_width())
end

---@return string
local function name_line()
  return string.format("%s", session.problem.name or "Pretest")
end

---@return string
local function limits_line()
  local tl = session.problem.timeLimit or config.options.default_time_limit
  local ml = session.problem.memoryLimit
  return string.format("TL %dms │ ML %dMB", tl, ml)
end

---Rebuild header buffer (name, limits, separator, cases).
---Use when the row count or separator width may change; otherwise `patch_header`.
local function render_header()
  if not session or not session.bufs.header or not vim.api.nvim_buf_is_valid(session.bufs.header) then
    return
  end
  local n = #session.problem.tests
  local idx = session.index
  local layout = header_layout(n)

  local header = {
    name_line(),
    limits_line(),
    header_sep_line(),
    format_cases_label(),
  }
  for i = 1, n do
    local line = format_case_line(i, n, idx, session.results[i])
    header[#header + 1] = line
  end

  set_lines(session.bufs.header, header)
  vim.bo[session.bufs.header].modifiable = false
  vim.bo[session.bufs.header].modified = false
  apply_header_marks(session.bufs.header, layout, idx)
  session.header_n = n
  session.header_rows = #header
  session.drawn_index = idx
end

---@class pretest.HeaderPatch
---@field name? boolean
---@field limits? boolean
---@field summary? boolean # "Testcases AC/total" (+ Compiling/Stopped)
---@field cases? integer[] # case rows to redraw
---@field index? boolean # move the `[n]` marker from the drawn row to `session.index`

---Rewrite only the listed header rows and their extmarks. Falls back to a
---full `render_header` when the row structure no longer matches.
---@param spec pretest.HeaderPatch
local function patch_header(spec)
  if not session then
    return
  end
  local buf = session.bufs.header
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local n = #session.problem.tests
  if n ~= session.header_n or vim.api.nvim_buf_line_count(buf) ~= session.header_rows then
    render_header()
    return
  end
  local layout = header_layout(n)
  local idx = session.index

  ---@type table<integer, fun(): string>
  local rows = {}
  if spec.name then
    rows[layout.name_row] = name_line
  end
  if spec.limits then
    rows[layout.limits_row] = limits_line
  end
  if spec.summary then
    rows[layout.cases_label_row] = format_cases_label
  end
  local function add_case(i)
    if i and i >= 1 and i <= n then
      rows[layout.cases_start + i - 1] = function()
        return (format_case_line(i, n, idx, session.results[i]))
      end
    end
  end
  for _, i in ipairs(spec.cases or {}) do
    add_case(i)
  end
  if spec.index then
    add_case(session.drawn_index)
    add_case(idx)
  end

  vim.bo[buf].modifiable = true
  for row, build in pairs(rows) do
    local old = buf_line(buf, row)
    local new = build()
    vim.api.nvim_buf_clear_namespace(buf, HEADER_NS, row, row + 1)
    if new ~= old then
      -- set_text keeps the row (and any cursor on it) in place.
      vim.api.nvim_buf_set_text(buf, row, 0, row, #old, { new })
    end
    if row == layout.limits_row then
      mark_limits_row(buf, layout)
    elseif row == layout.cases_label_row then
      mark_label_row(buf, layout)
    elseif row >= layout.cases_start then
      mark_case_row(buf, layout, row - layout.cases_start + 1, idx)
    end
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  if spec.index then
    session.drawn_index = idx
  end
end

local function prune_winids()
  if not session then
    return
  end
  local kept = {}
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) then
      table.insert(kept, win)
    end
  end
  session.winids = kept
  for win in pairs(session.win_bufs) do
    if not vim.api.nvim_win_is_valid(win) then
      session.win_bufs[win] = nil
    end
  end
end

---Register a UI window and the UI buffer it must keep showing.
---@param win integer
---@param buf integer
local function track_win(win, buf)
  table.insert(session.winids, win)
  session.win_bufs[win] = buf
end

local EXTRA_TITLES = { re = "Runtime Error", stderr = "Stderr" }

---@param key "re"|"stderr"
---@param height integer
---@param width integer
---@param row integer
---@param col integer
---@return integer
local function ensure_float_extra_win(key, height, width, row, col)
  local buf = session.bufs[key]
  local win = find_win_for_buf(buf)
  local title = " " .. EXTRA_TITLES[key] .. " "
  if win then
    local wincfg = vim.api.nvim_win_get_config(win)
    wincfg.relative = "editor"
    wincfg.width = width
    wincfg.height = height
    wincfg.row = row
    wincfg.col = col
    pcall(vim.api.nvim_win_set_config, win, wincfg)
    return win
  end
  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    zindex = key == "re" and 54 or 55,
  })
  configure_win(win, "body")
  track_win(win, buf)
  return win
end

---@param key "re"|"stderr"
local function hide_float_extra_win(key)
  local win = find_win_for_buf(session.bufs[key])
  if win then
    pcall(vim.api.nvim_win_close, win, true)
    prune_winids()
  end
end

---@param key "re"|"stderr"
---@param height integer
---@return integer|nil
local function ensure_sidebar_extra_win(key, height)
  local buf = session.bufs[key]
  local win = find_win_for_buf(buf)
  if win then
    pcall(vim.api.nvim_win_set_height, win, height)
    set_winbar(win, EXTRA_TITLES[key])
    return win
  end
  local above
  if key == "stderr" then
    above = find_win_for_buf(session.bufs.re) or find_win_for_buf(session.bufs.output)
  else
    above = find_win_for_buf(session.bufs.output)
  end
  if not above then
    return nil
  end
  local prev = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(above)
  vim.cmd("belowright split")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  configure_win(win, "body")
  pcall(vim.api.nvim_win_set_height, win, height)
  set_winbar(win, EXTRA_TITLES[key])
  track_win(win, buf)
  if prev and vim.api.nvim_win_is_valid(prev) then
    pcall(vim.api.nvim_set_current_win, prev)
  end
  return win
end

---@param key "re"|"stderr"
local function hide_sidebar_extra_win(key)
  local win = find_win_for_buf(session.bufs[key])
  if win then
    pcall(vim.api.nvim_win_close, win, true)
    prune_winids()
  end
end

local function apply_float_layout(re_lines, err_lines)
  if not session or session.ui_mode ~= "float" then
    return
  end
  local width = resolved_float_width()
  local show_re = re_lines ~= nil
  local show_stderr = err_lines ~= nil
  local re_h = show_re and math.min(4, #re_lines + 1) or 0
  local stderr_h = show_stderr and math.min(8, #err_lines + 1) or 0
  local heights = compute_float_heights(show_re, re_h, show_stderr, stderr_h)

  local extra_n = (show_re and 1 or 0) + (show_stderr and 1 or 0)
  local n_sections = 4 + extra_n
  local content_h = heights.header
    + heights.input
    + heights.expected
    + heights.output
    + heights.re
    + heights.stderr
  local stack_h = content_h + n_sections * 2
  local row = math.max(0, math.floor((vim.o.lines - stack_h) / 2))
  local col = math.floor((vim.o.columns - width) / 2)

  local order = {
    { key = "header", buf = session.bufs.header },
    { key = "input", buf = session.bufs.input },
    { key = "expected", buf = session.bufs.expected },
    { key = "output", buf = session.bufs.output },
  }

  local y = row
  for _, sec in ipairs(order) do
    local win = find_win_for_buf(sec.buf)
    if win then
      local wincfg = vim.api.nvim_win_get_config(win)
      wincfg.relative = "editor"
      wincfg.width = width
      wincfg.height = heights[sec.key]
      wincfg.row = y
      wincfg.col = col
      pcall(vim.api.nvim_win_set_config, win, wincfg)
    end
    y = y + heights[sec.key] + 2
  end

  if show_re then
    ensure_float_extra_win("re", heights.re, width, y, col)
    y = y + heights.re + 2
  else
    hide_float_extra_win("re")
  end
  if show_stderr then
    ensure_float_extra_win("stderr", heights.stderr, width, y, col)
  else
    hide_float_extra_win("stderr")
  end
end

---Run `fn` with `session.applying` set, restoring the previous value (nesting-safe).
---Blocks synchronous UI autocmds (e.g. WinClosed) from reacting to our own edits.
---@param fn fun()
local function with_applying(fn)
  local s = session
  if not s then
    return
  end
  local prev = s.applying
  s.applying = true
  local ok, err = pcall(fn)
  s.applying = prev
  if not ok then
    error(err, 0)
  end
end

---@class pretest.ResultView
---@field out string[]
---@field re string[]|nil # nil hides the Runtime Error section
---@field err string[]|nil # nil hides the Stderr section

---Body lines for Output / Runtime Error / Stderr of the current case.
---@return pretest.ResultView
local function result_view()
  local result = current_result()
  local verdict = result and result.verdict or "Pending"
  local out = result and util.split_lines(result.stdout) or { "" }
  local re = nil
  if verdict == "RE" then
    re = util.split_lines((result and result.reason_detail) or "runtime error")
  end
  local err_text = ""
  if result and result.stderr and result.stderr ~= "" then
    err_text = result.stderr
  elseif session.compile_stderr and session.compile_stderr ~= "" and verdict == "CE" then
    err_text = session.compile_stderr
  end
  local err = err_text ~= "" and util.split_lines(err_text) or nil
  return { out = out, re = re, err = err }
end

---@param buf integer
---@param body string[]
local function set_readonly_body(buf, body)
  -- Skip identical bodies so cursor/scroll in the window survive unrelated updates.
  if not vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), body) then
    set_lines(buf, body)
  end
  apply_empty_eol_marks(buf)
  vim.bo[buf].modifiable = false
end

---Fill Output / Runtime Error / Stderr buffers for the current case.
---@param view pretest.ResultView|nil
local function render_result(view)
  if not session then
    return
  end
  view = view or result_view()
  set_readonly_body(session.bufs.output, view.out)
  set_readonly_body(session.bufs.re, view.re or { "" })
  set_readonly_body(session.bufs.stderr, view.err or { "" })
end

---Open/close RE and Stderr windows and size the sections. Skips window calls
---when nothing that affects geometry changed since the last layout.
---@param opts { force?: boolean, view?: pretest.ResultView }|nil
local function render_layout(opts)
  if not session or not M.is_open() then
    return
  end
  opts = opts or {}
  local view = opts.view or result_view()
  local re_h = view.re and math.min(4, #view.re + 1) or 0
  local stderr_h = view.err and math.min(8, #view.err + 1) or 0
  local key = table.concat({
    session.ui_mode,
    re_h,
    stderr_h,
    header_content_min(#session.problem.tests),
    vim.o.columns,
    vim.o.lines,
  }, ":")
  if not opts.force and session.layout_key == key then
    return
  end
  with_applying(function()
    if session.ui_mode == "sidebar" then
      if view.re then
        ensure_sidebar_extra_win("re", re_h)
      else
        hide_sidebar_extra_win("re")
      end
      if view.err then
        ensure_sidebar_extra_win("stderr", stderr_h)
      else
        hide_sidebar_extra_win("stderr")
      end
      apply_sidebar_section_heights(re_h + stderr_h)
    else
      apply_float_layout(view.re, view.err)
    end
  end)
  session.layout_key = key
end

---Result buffers, then geometry (only if it changed).
local function refresh_result_view()
  local view = result_view()
  render_result(view)
  render_layout({ view = view })
end

local WINBARS = {
  input = "Input",
  expected = "Expected",
  output = "Output",
  re = "Runtime Error",
  stderr = "Stderr",
  header = "Pretest",
}

local function apply_winbars()
  if not session then
    return
  end
  local sidebar = session.ui_mode == "sidebar"
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) then
      if sidebar then
        local buf = vim.api.nvim_win_get_buf(win)
        for key, title in pairs(WINBARS) do
          if session.bufs[key] == buf then
            set_winbar(win, title)
          end
        end
      else
        -- Floats use border titles.
        set_winbar(win, "")
      end
    end
  end
end

---Redraw every section. Used when windows open or the problem/source changes.
local function render_all()
  if not session then
    return
  end
  with_applying(function()
    load_edit_bufs()
    local view = result_view()
    render_result(view)
    apply_winbars()
    render_layout({ force = true, view = view })
    -- After layout so the separator uses the final header width.
    render_header()
  end)
end

---Switch the visible testcase: save edits, move the `[n]` marker, reload bodies.
---@param index integer
local function show_case(index)
  if not session then
    return
  end
  M.flush_edits()
  session.index = index
  with_applying(function()
    patch_header({ index = true })
    load_edit_bufs()
    refresh_result_view()
  end)
end

local UI_KEY_ACTIONS = {
  next_case = function()
    M.next_case()
  end,
  prev_case = function()
    M.prev_case()
  end,
  close = function()
    M.close()
  end,
  stop = function()
    M.stop()
  end,
  run_all = function()
    local s = M.ensure_session()
    if not s then
      return
    end
    M.run(util.all_indices(#s.problem.tests), true)
  end,
  run_one = function()
    M.run({ session and session.index }, true)
  end,
  run_all_no_compile = function()
    local s = M.ensure_session()
    if not s then
      return
    end
    M.run(util.all_indices(#s.problem.tests), false)
  end,
  run_one_no_compile = function()
    M.run({ session and session.index }, false)
  end,
  next_section = function()
    focus_section(1)
  end,
  prev_section = function()
    focus_section(-1)
  end,
  add = function()
    M.add_testcase()
  end,
  ---`{count}{lhs}` deletes testcase {count}; `{lhs}{lhs}` deletes the current one.
  ---Reads the second key itself, so there is no `{lhs}` / `{lhs}{lhs}` timeoutlen wait.
  ---@param bind pretest.UiKeyBinding
  delete = function(bind)
    local count = vim.v.count
    if count > 0 then
      M.delete_testcase(count)
      return
    end
    local target = vim.keycode(bind.lhs)
    local typed = ""
    while #typed < #target do
      local ok, key = pcall(vim.fn.getcharstr)
      if not ok then
        return
      end
      typed = typed .. key
      if target:sub(1, #typed) ~= typed then
        return
      end
    end
    M.delete_testcase()
  end,
  help = function()
    M.help()
  end,
}

---Help / keymap `desc` order and labels.
local UI_KEY_HELP = {
  { "next_case", "Next testcase" },
  { "prev_case", "Previous testcase" },
  { "next_section", "Next section" },
  { "prev_section", "Previous section" },
  { "run_one", "Run current testcase" },
  { "run_all", "Run all testcases" },
  { "run_one_no_compile", "Run current testcase (no compile)" },
  { "run_all_no_compile", "Run all testcases (no compile)" },
  { "stop", "Stop run" },
  { "add", "Add testcase" },
  { "delete", "Delete testcase" },
  { "close", "Close UI" },
  { "help", "Show keys" },
}

---@type table<string, string>
local UI_KEY_DESC = {}
for _, item in ipairs(UI_KEY_HELP) do
  UI_KEY_DESC[item[1]] = item[2]
end

---Buffer kinds each `pretest.UiKeyScope` reaches.
local SCOPE_KINDS = {
  all = { edit = true, readonly = true, header = true },
  readonly = { readonly = true, header = true },
  header = { header = true },
}

---@param buf integer
---@param kind "edit"|"readonly"|"header"
local function map_ui_keys(buf, kind)
  -- UI buffers outlive a layout; drop earlier maps so a changed `ui_keys` leaves none behind.
  for _, m in ipairs(vim.b[buf].pretest_ui_maps or {}) do
    pcall(vim.keymap.del, m[1], m[2], { buffer = buf })
  end
  local mapped = {}
  for name, fn in pairs(UI_KEY_ACTIONS) do
    for _, bind in ipairs(config.ui_key_list(name)) do
      if SCOPE_KINDS[bind.scope][kind] then
        vim.keymap.set(bind.modes, bind.lhs, function()
          fn(bind)
        end, { buffer = buf, silent = true, nowait = true, desc = UI_KEY_DESC[name] })
        mapped[#mapped + 1] = { bind.modes, bind.lhs }
      end
    end
  end
  vim.b[buf].pretest_ui_maps = mapped
end

local function setup_buf_autocmds()
  if not session then
    return
  end
  local group = vim.api.nvim_create_augroup("pretest_ui_" .. session.bufs.input, { clear = true })
  for _, buf in ipairs({ session.bufs.input, session.bufs.expected }) do
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      group = group,
      buffer = buf,
      callback = function()
        M.flush_edits()
        vim.bo[buf].modified = false
      end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      buffer = buf,
      callback = function()
        apply_empty_eol_marks(buf)
      end,
    })
    map_ui_keys(buf, "edit")
  end
  map_ui_keys(session.bufs.header, "header")
  for _, buf in ipairs({ session.bufs.output, session.bufs.re, session.bufs.stderr }) do
    map_ui_keys(buf, "readonly")
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = session.bufs.header,
    callback = function()
      if not session or session.applying then
        return
      end
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(win) ~= session.bufs.header then
        return
      end
      local row = vim.api.nvim_win_get_cursor(win)[1] - 1
      local n = #session.problem.tests
      if n == 0 then
        return
      end
      local layout = header_layout(n)
      if row < layout.cases_start or row >= layout.cases_start + n then
        return
      end
      local index = row - layout.cases_start + 1
      if index == session.index then
        return
      end
      show_case(index)
      -- Keep focus on the selected case row in the header.
      session.applying = true
      pcall(vim.api.nvim_win_set_cursor, win, { layout.cases_start + index, 0 })
      session.applying = false
    end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if not session or session.applying then
        return
      end
      local header_win = find_win_for_buf(session.bufs.header)
      if not header_win then
        return
      end
      local resized = vim.v.event and vim.v.event.windows or nil
      if type(resized) == "table" then
        local hit = false
        for _, w in ipairs(resized) do
          if w == header_win then
            hit = true
            break
          end
        end
        if not hit then
          return
        end
      end
      -- The separator spans the header width.
      render_header()
    end,
  })
end

local function open_sidebar_column()
  if config.options.sidebar_position == "left" then
    vim.cmd("topleft vsplit")
  else
    vim.cmd("botright vsplit")
  end
  local root = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(root, resolved_sidebar_width())
  vim.api.nvim_win_set_buf(root, session.bufs.header)
  configure_win(root, "header")
  track_win(root, session.bufs.header)

  local sections = {
    { buf = session.bufs.input },
    { buf = session.bufs.expected },
    { buf = session.bufs.output },
  }
  for _, sec in ipairs(sections) do
    vim.cmd("belowright split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, sec.buf)
    configure_win(win, "body")
    track_win(win, sec.buf)
  end

  apply_sidebar_section_heights(0)
end

local function open_float_stack()
  local width = resolved_float_width()
  -- Runtime Error / Stderr floats are created later in apply_float_layout.
  local heights = compute_float_heights(false, 0, false, 0)
  local content_h = heights.header + heights.input + heights.expected + heights.output
  local stack_h = content_h + 4 * 2
  local row = math.max(0, math.floor((vim.o.lines - stack_h) / 2))
  local col = math.floor((vim.o.columns - width) / 2)

  local order = {
    { key = "header", buf = session.bufs.header, title = " Pretest " },
    { key = "input", buf = session.bufs.input, title = " Input " },
    { key = "expected", buf = session.bufs.expected, title = " Expected " },
    { key = "output", buf = session.bufs.output, title = " Output " },
  }

  local y = row
  for i, sec in ipairs(order) do
    local h = heights[sec.key]
    local win = vim.api.nvim_open_win(sec.buf, i == 2, {
      relative = "editor",
      width = width,
      height = h,
      row = y,
      col = col,
      style = "minimal",
      border = "rounded",
      title = sec.title,
      title_pos = "center",
      zindex = 50 + i,
    })
    configure_win(win, sec.key == "header" and "header" or "body")
    track_win(win, sec.buf)
    y = y + h + 2
  end
end

local function open_layout(mode)
  session.ui_mode = mode
  session.winids = {}
  session.win_bufs = {}
  session.layout_key = nil
  if mode == "float" then
    open_float_stack()
  else
    open_sidebar_column()
  end
end

---@param src_path string
---@return { results: table<integer, pretest.CaseResult>, index: integer, compile_stderr: string, compile_status?: "stopped"|nil }, boolean
local function state_for(src_path)
  if session and session.src_path == src_path then
    return session, true
  end
  local p = parked[src_path]
  if not p then
    p = { results = {}, index = 1, compile_stderr = "" }
    parked[src_path] = p
  end
  return p, false
end

local function park_current()
  if not session then
    return
  end
  M.flush_edits()
  parked[session.src_path] = {
    results = session.results,
    index = session.index,
    compile_stderr = session.compile_stderr,
  }
end

---@param src_bufnr integer
---@param abs string
---@param ft string
local function switch_source(src_bufnr, abs, ft)
  park_current()
  local problem, ppath = prob.load_or_create(abs)
  local saved = parked[abs]
  session.src_bufnr = src_bufnr
  session.src_path = abs
  session.filetype = ft
  session.problem = problem
  session.prob_path = ppath
  if saved then
    session.results = saved.results
    session.compile_stderr = saved.compile_stderr
    session.compile_status = nil
    local n = #problem.tests
    if n == 0 then
      session.index = 0
    else
      session.index = math.min(math.max(saved.index, 1), n)
    end
    parked[abs] = nil
  else
    session.results = {}
    session.compile_stderr = ""
    session.compile_status = nil
    if #problem.tests == 0 then
      session.index = 0
    else
      session.index = 1
    end
  end
  load_edit_bufs()
end

---@param bufnr integer
---@return boolean
local function is_transient_buf(bufnr)
  if is_ui_buf(bufnr) then
    return true
  end
  local win = vim.api.nvim_get_current_win()
  if win and vim.api.nvim_win_is_valid(win) then
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative and cfg.relative ~= "" then
      return true
    end
  end
  local bt = vim.bo[bufnr].buftype
  return bt ~= ""
end

---@param bufnr integer
---@return string|nil abs
---@return string|nil ft
local function source_of(bufnr)
  local path, ft = util.source_from_buf(bufnr)
  if not path or not util.supported_filetype(ft) then
    return nil, nil
  end
  return util.abspath(path), ft
end

---Point the open UI at a visible source buffer.
---@param bufnr integer
---@param abs string
---@param ft string
local function adopt_source(bufnr, abs, ft)
  if session.src_path == abs then
    session.src_bufnr = bufnr
    session.filetype = ft
    return
  end
  switch_source(bufnr, abs, ft)
  render_all()
end

follow_visible_source = function()
  if not session or not M.is_open() or session.applying then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if is_transient_buf(bufnr) then
    return
  end
  local abs, ft = source_of(bufnr)
  if not abs then
    M.close()
    return
  end
  adopt_source(bufnr, abs, ft)
end

---@param win integer
---@return boolean
local function is_float_win(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

---Non-UI, non-float windows of `tab`: where source buffers are edited.
---@param tab integer
---@return integer[]
local function main_candidates(tab)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if not session.win_bufs[win] and not is_float_win(win) then
      table.insert(wins, win)
    end
  end
  return wins
end

---First open UI window; the header in sidebar mode (tracked first).
---@return integer|nil
local function first_ui_win()
  for _, win in ipairs(session.winids) do
    if vim.api.nvim_win_is_valid(win) then
      return win
    end
  end
  return nil
end

---@return integer|nil
local function ui_tabpage()
  local win = first_ui_win()
  return win and vim.api.nvim_win_get_tabpage(win)
end

---Window that should receive a buffer opened inside `ui_win`.
---@param ui_win integer
---@return integer|nil
local function pick_main_win(ui_win)
  local cands = main_candidates(vim.api.nvim_win_get_tabpage(ui_win))
  for _, win in ipairs(cands) do
    if vim.api.nvim_win_get_buf(win) == session.src_bufnr then
      return win
    end
  end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if vim.tbl_contains(cands, prev) then
    return prev
  end
  for _, win in ipairs(cands) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
      return win
    end
  end
  return cands[1]
end

---@param win integer
---@param buf integer
local function restore_ui_win(win, buf)
  vim.api.nvim_win_set_buf(win, buf)
  configure_win(win, buf == session.bufs.header and "header" or "body")
  if session.ui_mode == "sidebar" then
    for key, b in pairs(session.bufs) do
      if b == buf then
        set_winbar(win, WINBARS[key])
      end
    end
  end
end

---A buffer was displayed in the current window: if that is a UI window, put the
---UI buffer back and move the newcomer to the main window (e.g. bufferline clicks).
---@param bufnr integer
guard_ui_win = function(bufnr)
  if not session or session.applying or session.closing or not M.is_open() then
    return
  end
  -- BufWinEnter runs with the receiving window as the current window.
  local win = vim.api.nvim_get_current_win()
  local ui_buf = session.win_bufs[win]
  if not ui_buf or bufnr == ui_buf or vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end
  if not vim.api.nvim_buf_is_valid(ui_buf) then
    return
  end
  local dest
  with_applying(function()
    restore_ui_win(win, ui_buf)
    if is_ui_buf(bufnr) then
      return
    end
    dest = pick_main_win(win)
    if not dest then
      return
    end
    -- A buffer never shown in `dest` would inherit the UI window's options.
    local opts = get_win_opts(dest)
    vim.api.nvim_win_set_buf(dest, bufnr)
    set_win_opts(dest, opts)
  end)
  if dest then
    vim.api.nvim_set_current_win(dest)
    vim.cmd.stopinsert()
  end
end

---`:quit` is about to close the window showing `bufnr`. If only UI windows would
---remain in the tab, close the UI first so the quit closes the tab / Neovim.
---@param bufnr integer
before_quit = function(bufnr)
  if session.closing or not M.is_open() then
    return
  end
  local tab = vim.api.nvim_get_current_tabpage()
  if ui_tabpage() ~= tab then
    return
  end
  local cands = main_candidates(tab)
  if #cands == 1 and vim.api.nvim_win_get_buf(cands[1]) == bufnr then
    M.close()
  end
end

---Only UI windows are left: Neovim needs one window, so turn one of them into an
---empty editing window and close the rest.
local function replace_ui_with_empty()
  local keep = first_ui_win()
  if not keep or is_float_win(keep) then
    M.close()
    return
  end
  with_applying(function()
    vim.api.nvim_win_set_buf(keep, vim.api.nvim_create_buf(true, false))
    session.win_bufs[keep] = nil
    session.winids = vim.tbl_filter(function(w)
      return w ~= keep
    end, session.winids)
    reset_win_opts(keep)
  end)
  M.close()
end

---A non-UI window in `tab` was closed by something other than `:quit`.
---@param tab integer
after_win_closed = function(tab)
  if not session or session.closing or not M.is_open() then
    return
  end
  local ui_tab = ui_tabpage()
  if ui_tab ~= tab then
    return
  end
  local cands = main_candidates(ui_tab)
  if #cands == 0 then
    replace_ui_with_empty()
    return
  end
  -- Focus landed in a normal window: its BufEnter → follow_visible_source decides.
  local cur = vim.api.nvim_get_current_win()
  if not session.win_bufs[cur] and not is_float_win(cur) then
    return
  end
  -- Focus is in the UI (or a float), which follow_visible_source skips.
  local pick
  for _, win in ipairs(cands) do
    local buf = vim.api.nvim_win_get_buf(win)
    local abs, ft = source_of(buf)
    if abs then
      if buf == session.src_bufnr then
        pick = { buf, abs, ft }
        break
      end
      pick = pick or { buf, abs, ft }
    end
  end
  if pick then
    adopt_source(pick[1], pick[2], pick[3])
  else
    M.close()
  end
end

---@param src_bufnr integer|nil
function M.ensure_session(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()

  if is_ui_buf(src_bufnr) then
    if session then
      return session
    end
    util.notify("no Pretest session — open from a source file", vim.log.levels.ERROR)
    return nil
  end

  local path, ft = util.source_from_buf(src_bufnr)
  if not path or not ft then
    util.notify("no file in current buffer", vim.log.levels.ERROR)
    return nil
  end

  if not util.supported_filetype(ft) then
    util.notify("unsupported filetype: " .. util.filetype_label(ft), vim.log.levels.ERROR)
    return nil
  end

  local abs = util.abspath(path)
  -- Reuse existing session for the same source even when UI is closed,
  -- so ui_mode / results survive close.
  if session and session.src_path == abs then
    session.src_bufnr = src_bufnr
    session.filetype = ft
    return session
  end

  if session then
    local was_open = M.is_open()
    switch_source(src_bufnr, abs, ft)
    if was_open then
      render_all()
    end
    return session
  end

  local problem, ppath = prob.load_or_create(path)
  session = {
    src_bufnr = src_bufnr,
    src_path = abs,
    filetype = ft,
    problem = problem,
    prob_path = ppath,
    index = math.min(1, math.max(#problem.tests, 1)),
    results = {},
    ui_mode = get_preferred_ui(),
    winids = {},
    win_bufs = {},
    bufs = {
      header = make_buf("pretest://header", false),
      input = make_buf("pretest://input", true),
      expected = make_buf("pretest://expected", true),
      output = make_buf("pretest://output", false),
      re = make_buf("pretest://re", false),
      stderr = make_buf("pretest://stderr", false),
    },
    applying = false,
    closing = false,
    compile_stderr = "",
    compile_status = nil,
  }
  if #problem.tests == 0 then
    session.index = 0
  else
    session.index = 1
  end
  load_edit_bufs()
  return session
end

function M.show()
  local s = M.ensure_session()
  if not s then
    return
  end
  if M.is_open() then
    for _, win in ipairs(s.winids) do
      if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == s.bufs.input then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
    return
  end
  s.compile_status = nil
  open_layout(s.ui_mode)
  setup_buf_autocmds()
  render_all()
  for _, win in ipairs(s.winids) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == s.bufs.input then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
end

local function focus_header()
  local win = session and find_win_for_buf(session.bufs.header)
  if win then
    vim.api.nvim_set_current_win(win)
    sync_header_cursor(win)
  end
end

---Jump between the source and the UI header, opening the UI when closed.
---From the UI: back to the source in sidebar mode; float mode (which covers it) closes.
function M.focus()
  if not M.is_open() then
    M.show()
    if M.is_open() then
      focus_header()
    end
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if not session.win_bufs[cur] then
    focus_header()
    return
  end
  if session.ui_mode == "float" then
    M.close()
    return
  end
  local dest = pick_main_win(cur)
  if dest then
    vim.api.nvim_set_current_win(dest)
  end
end

---@type integer|nil
local help_win = nil

local function close_help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    pcall(vim.api.nvim_win_close, help_win, true)
  end
  help_win = nil
end

---@return string[] lines
---@return { row: integer, col: integer, end_col: integer, hl: string }[] marks
local function help_content()
  local groups = {
    { scope = "all", title = "All sections", rows = {} },
    { scope = "readonly", title = "Header & results", rows = {} },
    { scope = "header", title = "Header", rows = {} },
  }
  local by_scope = {}
  for _, g in ipairs(groups) do
    by_scope[g.scope] = g
  end
  for _, item in ipairs(UI_KEY_HELP) do
    local name, desc = item[1], item[2]
    local keys = {}
    for _, bind in ipairs(config.ui_key_list(name)) do
      keys[bind.scope] = keys[bind.scope] or {}
      table.insert(keys[bind.scope], bind.lhs)
    end
    for scope, lhs_list in pairs(keys) do
      local rows = by_scope[scope].rows
      if name == "delete" then
        for _, lhs in ipairs(lhs_list) do
          table.insert(rows, { lhs .. lhs, "Delete current testcase" })
          table.insert(rows, { "{count}" .. lhs, "Delete testcase {count}" })
        end
      else
        table.insert(rows, { table.concat(lhs_list, " / "), desc })
      end
    end
  end
  table.insert(groups, {
    title = "Other",
    rows = {
      { ":w", "Save Input / Expected" },
      { "Header case row", "Select that testcase" },
    },
  })

  local key_w = 0
  for _, g in ipairs(groups) do
    for _, row in ipairs(g.rows) do
      key_w = math.max(key_w, vim.fn.strdisplaywidth(row[1]))
    end
  end
  local lines, marks = {}, {}
  for _, g in ipairs(groups) do
    if #g.rows > 0 then
      if #lines > 0 then
        lines[#lines + 1] = ""
      end
      lines[#lines + 1] = " " .. g.title
      marks[#marks + 1] = { row = #lines - 1, col = 1, end_col = 1 + #g.title, hl = "Title" }
      for _, row in ipairs(g.rows) do
        local key, desc = row[1], row[2]
        local pad = string.rep(" ", key_w - vim.fn.strdisplaywidth(key) + 2)
        lines[#lines + 1] = "   " .. key .. pad .. desc .. " "
        local r = #lines - 1
        marks[#marks + 1] = { row = r, col = 3, end_col = 3 + #key, hl = "PretestKey" }
        local dcol = 3 + #key + #pad
        marks[#marks + 1] = { row = r, col = dcol, end_col = dcol + #desc, hl = "PretestHint" }
      end
    end
  end
  return lines, marks
end

---Toggle a float listing the UI keys (built from the actual `ui_keys`).
function M.help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    close_help()
    return
  end
  local lines, marks = help_content()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ns = vim.api.nvim_create_namespace("pretest_help")
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m.row, m.col, { end_col = m.end_col, hl_group = m.hl })
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "pretest_help"

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width, math.max(1, vim.o.columns - 4))
  local height = math.min(#lines, math.max(1, vim.o.lines - 4))
  help_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Pretest keys ",
    title_pos = "center",
    zindex = 100,
  })
  for _, lhs in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", lhs, close_help, { buffer = buf, silent = true, nowait = true })
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(close_help)
    end,
  })
end

function M.toggle_layout()
  local current_mode = session and session.ui_mode or get_preferred_ui()
  local next_mode = current_mode == "sidebar" and "float" or "sidebar"
  preferred_ui = next_mode
  if session then
    session.ui_mode = next_mode
  end
  if M.is_open() then
    M.flush_edits()
    M.close()
    open_layout(next_mode)
    setup_buf_autocmds()
    render_all()
  else
    util.notify("UI mode: " .. next_mode)
  end
end

function M.next_case()
  if not session or #session.problem.tests == 0 then
    return
  end
  show_case(session.index % #session.problem.tests + 1)
  sync_header_cursor()
end

function M.prev_case()
  if not session or #session.problem.tests == 0 then
    return
  end
  local index = session.index - 1
  if index < 1 then
    index = #session.problem.tests
  end
  show_case(index)
  sync_header_cursor()
end

---@param index integer|nil
function M.goto_case(index)
  local s = M.ensure_session()
  if not s then
    return
  end
  if not M.is_open() then
    M.show()
  end
  if #s.problem.tests == 0 then
    util.notify("no testcases", vim.log.levels.WARN)
    return
  end
  index = index or s.index
  if index < 1 or index > #s.problem.tests then
    util.notify("invalid testcase index", vim.log.levels.ERROR)
    return
  end
  show_case(index)
  for _, win in ipairs(s.winids) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == s.bufs.input then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
end

function M.add_testcase()
  local s = M.ensure_session()
  if not s then
    return
  end
  M.flush_edits()
  prob.add_testcase(s.problem)
  s.index = #s.problem.tests
  s.results[s.index] = nil
  prob.save(s.problem, s.prob_path)
  if M.is_open() then
    -- Row count changed and the new case is now visible.
    with_applying(function()
      render_header()
      load_edit_bufs()
      refresh_result_view()
    end)
  end
  -- Opens the UI if needed and puts the cursor in Input to fill in the new case.
  M.show()
end

function M.edit_limits()
  local s = M.ensure_session()
  if not s then
    return
  end
  local cfg = config.options
  local cur_tl = s.problem.timeLimit or cfg.default_time_limit
  local cur_ml = s.problem.memoryLimit

  local function parse_positive_int(val, label)
    local n = tonumber(val)
    if not n or n ~= math.floor(n) or n <= 0 then
      util.notify("invalid " .. label, vim.log.levels.ERROR)
      return nil
    end
    return n
  end

  ---@param val string
  ---@param label string
  ---@return integer|nil
  local function parse_nonneg_int(val, label)
    local n = tonumber(val)
    if not n or n ~= math.floor(n) or n < 0 then
      util.notify("invalid " .. label, vim.log.levels.ERROR)
      return nil
    end
    return n
  end

  vim.ui.input({ prompt = "Time limit (ms): ", default = tostring(cur_tl) }, function(time_s)
    if time_s == nil then
      return
    end
    local time_n = parse_positive_int(time_s, "time limit")
    if not time_n then
      return
    end
    vim.ui.input({ prompt = "Memory limit (MB, 0=off): ", default = tostring(cur_ml) }, function(mem_s)
      if mem_s == nil then
        return
      end
      local mem_n = parse_nonneg_int(mem_s, "memory limit")
      if mem_n == nil then
        return
      end
      s.problem.timeLimit = time_n
      s.problem.memoryLimit = mem_n
      prob.save(s.problem, s.prob_path)
      if M.is_open() then
        patch_header({ limits = true })
      end
    end)
  end)
end

function M.edit_name()
  local s = M.ensure_session()
  if not s then
    return
  end
  local cur = s.problem.name or "Pretest"

  vim.ui.input({ prompt = "Problem name: ", default = cur }, function(name)
    if name == nil then
      return
    end
    s.problem.name = name
    prob.save(s.problem, s.prob_path)
    if M.is_open() then
      patch_header({ name = true })
    end
  end)
end

---Stop an in-flight compile/run without notifying when nothing is running.
---@param s pretest.Session
---@return boolean
local function stop_run(s)
  local was_compiling = runner.is_compiling(s.src_path)
  if not runner.stop(s.src_path) then
    return false
  end
  if was_compiling then
    s.compile_status = "stopped"
  else
    for _, r in pairs(s.results) do
      if r.verdict == "Running" then
        r.verdict = "Stopped"
      end
    end
  end
  return true
end

---Drop `deleted` and shift later result slots down. Sparse keys are remapped
---explicitly so `#results` holes do not drop later verdicts.
---@param results table<integer, pretest.CaseResult>
---@param deleted integer
---@return table<integer, pretest.CaseResult>
local function remap_results(results, deleted)
  local removed = {}
  for i, r in pairs(results) do
    if type(i) == "number" then
      if i < deleted then
        removed[i] = r
      elseif i > deleted then
        removed[i - 1] = r
      end
    end
  end
  return removed
end

---@param index integer|nil
function M.delete_testcase(index)
  local s = M.ensure_session()
  if not s then
    return
  end
  if #s.problem.tests == 0 then
    util.notify("no testcases", vim.log.levels.WARN)
    return
  end
  index = index or s.index
  if index < 1 or index > #s.problem.tests then
    util.notify("invalid testcase index", vim.log.levels.ERROR)
    return
  end
  if vim.fn.confirm(("Delete testcase %d?"):format(index), "&Yes\n&No", 2) ~= 1 then
    return
  end
  M.flush_edits()
  stop_run(s)
  prob.delete_testcase(s.problem, index)
  s.results = remap_results(s.results, index)
  if #s.problem.tests == 0 then
    s.index = 0
  else
    s.index = math.min(index, #s.problem.tests)
  end
  prob.save(s.problem, s.prob_path)
  -- Even with the UI closed: flush_edits later reads these buffers into tests[index].
  load_edit_bufs()
  if M.is_open() then
    with_applying(function()
      render_header()
      refresh_result_view()
    end)
  end
end

---Return true if language run config for `src_path`/`ft` is usable; otherwise notify and return false.
---@param src_path string
---@param ft string
---@return boolean
local function check_lang_config(src_path, ft)
  local lang = config.language(ft)
  if not lang or not lang.run then
    util.notify("unsupported filetype: " .. util.filetype_label(ft), vim.log.levels.ERROR)
    return false
  end
  local exec = lang.run.exec
  if type(exec) == "function" then
    exec = exec({
      src_path = util.abspath(src_path),
      bin_path = runner.bin_path_for(src_path),
    })
  end
  if type(exec) ~= "string" then
    util.notify(
      "run.exec not configured for filetype: " .. util.filetype_label(ft),
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

---@param indices integer[] 1-based indices to run (must be non-empty)
---@param do_compile boolean
function M.run(indices, do_compile)
  local s = M.ensure_session()
  if not s then
    return
  end
  if #s.problem.tests == 0 then
    util.notify("no testcases — use :Pretest add", vim.log.levels.WARN)
    return
  end
  if not indices or #indices == 0 then
    util.notify("no testcases selected", vim.log.levels.WARN)
    return
  end
  if not check_lang_config(s.src_path, s.filetype) then
    return
  end
  if s.src_bufnr and vim.api.nvim_buf_is_valid(s.src_bufnr) and vim.bo[s.src_bufnr].modified then
    vim.api.nvim_buf_call(s.src_bufnr, function()
      vim.cmd("write")
    end)
  end
  M.flush_edits()
  if not M.is_open() then
    M.show()
  end

  s.compile_stderr = ""
  s.compile_status = nil
  for _, i in ipairs(indices) do
    s.results[i] = {
      verdict = "Pending",
      stdout = "",
      stderr = "",
    }
  end
  -- Always refresh the result view: clearing compile_stderr can hide a CE Stderr.
  with_applying(function()
    patch_header({ cases = indices, summary = true })
    refresh_result_view()
  end)

  local run_src = s.src_path

  ---Update the header rows for `cases` (+ summary) and, when the visible case
  ---is among them, its result sections. No-op unless this source's UI is open.
  ---@param live boolean
  ---@param cases integer[]|nil
  ---@param result_changed boolean|nil
  local function update(live, cases, result_changed)
    if not live or not M.is_open() then
      return
    end
    with_applying(function()
      patch_header({ cases = cases, summary = true })
      if result_changed then
        refresh_result_view()
      end
    end)
  end

  runner.run_tests(s.src_path, s.filetype, s.problem, indices, do_compile, {
    on_compile_start = function()
      local st, live = state_for(run_src)
      st.compile_stderr = ""
      update(live)
    end,
    on_compile_done = function(ok, stderr)
      local st, live = state_for(run_src)
      if not ok then
        st.compile_stderr = stderr
      end
      -- A visible CE case shows compile stderr even if it is not in this run.
      update(live, nil, not ok)
    end,
    on_case_start = function(i)
      local st, live = state_for(run_src)
      st.results[i] = {
        verdict = "Running",
        stdout = "",
        stderr = "",
      }
      update(live, { i }, live and i == session.index)
    end,
    on_case_done = function(i, result)
      local st, live = state_for(run_src)
      st.results[i] = result
      update(live, { i }, live and i == session.index)
    end,
    on_all_done = function()
      local _, live = state_for(run_src)
      update(live)
    end,
  })
end

function M.stop()
  local s = session
  if not s then
    util.notify("no session", vim.log.levels.WARN)
    return
  end
  if not stop_run(s) then
    util.notify("not running")
    return
  end
  if M.is_open() then
    with_applying(function()
      -- Any Running row may have become Stopped; rows are cheap to patch.
      patch_header({ cases = util.all_indices(#s.problem.tests), summary = true })
      refresh_result_view()
    end)
  end
end

local function focus_input_win()
  if not session then
    return
  end
  for _, win in ipairs(session.winids) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == session.bufs.input then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

---Open UI for the existing session without resolving the current buffer.
local function ensure_ui_open()
  if not session then
    return
  end
  if M.is_open() then
    render_all()
    focus_input_win()
    return
  end
  open_layout(session.ui_mode)
  setup_buf_autocmds()
  render_all()
  focus_input_win()
end

---Open `src_path` in the current window as a listed buffer without `:edit`
---(which prompts to save / reloads and can discard unsaved changes).
---@param src_path string
local function open_source(src_path)
  local cur = vim.api.nvim_get_current_buf()
  local cur_name = vim.api.nvim_buf_get_name(cur)
  if cur_name ~= "" and util.abspath(cur_name) == src_path then
    return
  end

  if cur and vim.api.nvim_buf_is_valid(cur) and vim.bo[cur].buftype == "" then
    vim.bo[cur].buflisted = true
  end

  local bufnr = vim.fn.bufadd(src_path)
  if bufnr == 0 then
    return
  end
  vim.bo[bufnr].buflisted = true
  vim.fn.bufload(bufnr)
  if vim.api.nvim_get_current_buf() == bufnr then
    return
  end
  if vim.o.hidden then
    vim.api.nvim_set_current_buf(bufnr)
  else
    vim.cmd.buffer({
      args = { tostring(bufnr) },
      mods = { hide = true },
    })
  end
end

---Save `problem` for `src_path`, adopt it into the session, and show the UI.
---@param src_path string
---@param problem pretest.Problem
---@return boolean
function M.apply_problem(src_path, problem)
  src_path = util.abspath(src_path)
  problem.srcPath = src_path
  parked[src_path] = nil
  local ppath = prob.prob_path(src_path)
  if not prob.save(problem, ppath) then
    return false
  end

  local function adopt(s)
    s.problem = problem
    s.prob_path = ppath or s.prob_path
    s.results = {}
    s.compile_stderr = ""
    s.compile_status = nil
    if #problem.tests == 0 then
      s.index = 0
    else
      s.index = 1
    end
  end

  if session and session.src_path == src_path then
    adopt(session)
    ensure_ui_open()
    return true
  end

  local function focus_non_ui_win()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win and vim.api.nvim_win_is_valid(win) and not is_ui_buf(vim.api.nvim_win_get_buf(win)) then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end
  focus_non_ui_win()
  open_source(src_path)
  local s = M.ensure_session()
  if not s then
    return false
  end
  adopt(s)
  ensure_ui_open()
  return true
end

---@param dest string
---@param old_src string
---@param relative_to "src_dir"|"cwd"
---@return string
local function resolve_move_dest(dest, old_src, relative_to)
  dest = vim.fn.expand(dest)
  local abs
  if relative_to == "src_dir" and not dest:match("^/") and not dest:match("^%a:[/\\]") then
    local src_dir = vim.fn.fnamemodify(old_src, ":h")
    abs = util.abspath(vim.fs.joinpath(src_dir, dest))
  else
    abs = util.abspath(dest)
  end
  local as_dir = dest:match("[/\\]$") or vim.fn.isdirectory(abs) == 1
  if as_dir then
    abs = util.abspath(vim.fs.joinpath(abs, vim.fn.fnamemodify(old_src, ":t")))
  end
  return abs
end

---@param bufnr integer
---@param old_name string
local function wipe_leftover_buf(bufnr, old_name)
  if old_name == "" then
    return
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= bufnr and b and vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == old_name then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

---Rename or move the source file and reconnect `.prob` / binary / session.
---@param dest string|nil
---@param opts { relative_to?: "src_dir"|"cwd" }|nil
function M.move_source(dest, opts)
  opts = opts or {}
  local relative_to = opts.relative_to or "cwd"
  dest = dest and vim.trim(dest) or ""
  if dest == "" then
    if relative_to == "src_dir" then
      util.notify("usage: Pretest rename <name>", vim.log.levels.WARN)
    else
      util.notify("usage: Pretest move <path>", vim.log.levels.WARN)
    end
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local old_src, ft
  if is_ui_buf(bufnr) then
    if not session then
      util.notify("no Pretest session — open from a source file", vim.log.levels.ERROR)
      return
    end
    bufnr = session.src_bufnr
    old_src = session.src_path
    ft = session.filetype
  else
    old_src, ft = util.source_from_buf(bufnr)
    if not old_src or not ft then
      util.notify("no file in current buffer", vim.log.levels.ERROR)
      return
    end
    if not util.supported_filetype(ft) then
      util.notify("unsupported filetype: " .. util.filetype_label(ft), vim.log.levels.ERROR)
      return
    end
  end

  old_src = util.abspath(old_src)
  local new_src = resolve_move_dest(dest, old_src, relative_to)
  if new_src == old_src then
    util.notify("already at " .. new_src)
    return
  end

  local new_ft = util.filetype_from_path(new_src)
  if not util.supported_filetype(new_ft) then
    util.notify("unsupported destination filetype: " .. vim.fn.fnamemodify(new_src, ":t"), vim.log.levels.ERROR)
    return
  end

  if vim.fn.filereadable(new_src) == 1 or vim.fn.isdirectory(new_src) == 1 then
    util.notify("destination already exists: " .. new_src, vim.log.levels.ERROR)
    return
  end

  local new_prob = prob.prob_path(new_src)
  local old_prob = prob.prob_path(old_src)
  if new_prob and new_prob ~= old_prob and vim.fn.filereadable(new_prob) == 1 then
    util.notify("destination .prob already exists: " .. new_prob, vim.log.levels.ERROR)
    return
  end

  local live_session = nil
  if session and session.src_path == old_src then
    live_session = session
    M.flush_edits()
  end

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local needs_write = vim.bo[bufnr].modified or vim.fn.filereadable(old_src) == 0
    if needs_write then
      local ok, err = pcall(function()
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("write")
        end)
      end)
      if not ok then
        util.notify("failed to write source: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
    end
  elseif vim.fn.filereadable(old_src) == 0 then
    util.notify("source file not found: " .. old_src, vim.log.levels.ERROR)
    return
  end

  local parent = vim.fn.fnamemodify(new_src, ":h")
  if parent ~= "" and vim.fn.isdirectory(parent) == 0 then
    vim.fn.mkdir(parent, "p")
  end

  if live_session then
    live_session.applying = true
  end

  local function finish_applying()
    if live_session then
      live_session.applying = false
    end
  end

  if vim.fn.rename(old_src, new_src) ~= 0 then
    finish_applying()
    util.notify("failed to move " .. old_src .. " → " .. new_src, vim.log.levels.ERROR)
    return
  end

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local old_name = vim.api.nvim_buf_get_name(bufnr)
    pcall(vim.api.nvim_buf_set_name, bufnr, new_src)
    wipe_leftover_buf(bufnr, old_name)
  end

  local problem = nil
  if live_session then
    problem = live_session.problem
  end
  local relocated, new_ppath, err = prob.relocate(old_src, new_src, problem)
  runner.relocate_bin(old_src, new_src)

  if live_session then
    if parked[old_src] then
      parked[new_src] = parked[old_src]
      parked[old_src] = nil
    end
    live_session.src_path = new_src
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      live_session.src_bufnr = bufnr
    end
    live_session.filetype = new_ft
    live_session.prob_path = new_ppath
    if relocated then
      live_session.problem = relocated
    elseif live_session.problem then
      live_session.problem.srcPath = new_src
    end
  end

  finish_applying()
  if live_session and M.is_open() then
    render_all()
  end
  if err then
    util.notify(
      "source moved to " .. new_src .. " but .prob was not: " .. err,
      vim.log.levels.ERROR
    )
    return
  end
  util.notify(string.format("moved %s → %s", vim.fn.fnamemodify(old_src, ":t"), new_src))
end

return M
