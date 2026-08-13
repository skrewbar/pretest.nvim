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
---@field bufs { header: integer, input: integer, expected: integer, output: integer, stderr: integer }
---@field main_win integer|nil
---@field applying boolean
---@field compile_stderr string

---@type pretest.Session|nil
local session = nil

---Per-source results kept while the UI is showing another file.
---@type table<string, { results: table<integer, pretest.CaseResult>, index: integer, compile_stderr: string }>
local parked = {}

---Assigned after helpers exist; BufEnter in setup() closes over this upvalue.
local follow_visible_source

---Remembers last chosen UI mode for this Neovim session (falls back to config.ui).
---@type "sidebar"|"float"|nil
local preferred_ui = nil

---Remembers header hint visibility for this Neovim session (falls back to config).
---@type boolean|nil
local preferred_show_hints = nil

---Last header window width; used to re-apply heights when wrap extra changes.
---@type integer|nil
local last_header_wrap_width = nil

local HEADER_NS = vim.api.nvim_create_namespace("pretest_header")
local EMPTY_EOL_NS = vim.api.nvim_create_namespace("pretest_empty_eol")
local HEADER_HEIGHT_CAP = 36
local highlights_setup = false

---@return "sidebar"|"float"
local function get_preferred_ui()
  if preferred_ui == "sidebar" or preferred_ui == "float" then
    return preferred_ui
  end
  local ui = config.get().ui
  if ui == "float" then
    return "float"
  end
  return "sidebar"
end

---@param mode "sidebar"|"float"
local function set_preferred_ui(mode)
  preferred_ui = mode
end

---@return boolean
local function get_show_hints()
  if preferred_show_hints ~= nil then
    return preferred_show_hints
  end
  return config.get().show_header_hints ~= false
end

---@param show boolean
local function set_show_hints(show)
  preferred_show_hints = show
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

---@return integer
local function resolved_sidebar_width()
  local cfg = config.get()
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
  local cfg = config.get()
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
  local cfg = config.get()
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
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = body
  if body then
    vim.wo[win].listchars = "tab:>·,trail:-"
  end
  vim.wo[win].cursorline = false
  -- Sidebar last-used winbar is remembered on the buffer; floats use border titles.
  if session and session.ui_mode == "float" then
    set_winbar(win, "")
  end
end

---Mark completely empty lines with an eol indicator (listchars eol would mark every line).
---@param buf integer
local function apply_empty_eol_marks(buf)
  if not valid_buf(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, EMPTY_EOL_NS, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line == "" then
      -- overlay at col 0: eol virt_text on empty lines sits one column in and looks indented.
      vim.api.nvim_buf_set_extmark(buf, EMPTY_EOL_NS, i - 1, 0, {
        virt_text = { { "¬", "NonText" } },
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
    if valid_buf(buf) then
      vim.bo[buf].modified = false
    end
  end
end

---@param bufnr integer
---@return boolean
local function is_ui_buf(bufnr)
  if not valid_buf(bufnr) then
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
    PretestCE = "DiagnosticError",
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

-- Hint rows: { text, is_key } segments so shortcuts can be colored.
-- Wrap happens per hint unit (keys joined by `/` plus the following label).
local HINT_SEGMENTS = {
  {
    { "<C-n>", true },
    { "/", false },
    { "<C-p>", true },
    { " switch  ", false },
    { ":w", true },
    { " save  ", false },
    { "q", true },
    { " close", false },
  },
  {
    { "R", true },
    { " run-all  ", false },
    { "r", true },
    { " run-one  ", false },
    { "<C-S-r>", true },
    { " no-compile-all  ", false },
    { "<C-r>", true },
    { " no-compile-one", false },
  },
  {
    { "<Tab>", true },
    { "/", false },
    { "<S-Tab>", true },
    { " sections", false },
  },
}

---@alias pretest.HintSeg { [1]: string, [2]: boolean }

---Group segments into unsplittable hints: keys joined by `/`, plus the label.
---@param segs pretest.HintSeg[]
---@return pretest.HintSeg[][]
local function hint_units(segs)
  local units = {}
  local i = 1
  while i <= #segs do
    local unit = {}
    while i <= #segs do
      local text, is_key = segs[i][1], segs[i][2]
      if is_key or text == "/" then
        unit[#unit + 1] = segs[i]
        i = i + 1
      else
        break
      end
    end
    if i <= #segs and not segs[i][2] then
      unit[#unit + 1] = segs[i]
      i = i + 1
    end
    if #unit > 0 then
      units[#units + 1] = unit
    end
  end
  return units
end

---@param width integer|nil
---@return string[] lines
---@return { row: integer, col: integer, end_col: integer, hl: string }[] marks
local function build_hint_lines(width)
  width = (width and width > 0) and width or math.huge
  local lines = {}
  local marks = {}
  for _, segs in ipairs(HINT_SEGMENTS) do
    local row = #lines
    local col = 0
    local parts = {}
    for _, unit in ipairs(hint_units(segs)) do
      local unit_len = 0
      for _, seg in ipairs(unit) do
        unit_len = unit_len + #seg[1]
      end
      if col > 0 and col + unit_len > width then
        lines[#lines + 1] = table.concat(parts)
        parts = {}
        row = #lines
        col = 0
      end
      for _, seg in ipairs(unit) do
        local text, is_key = seg[1], seg[2]
        parts[#parts + 1] = text
        marks[#marks + 1] = {
          row = row,
          col = col,
          end_col = col + #text,
          hl = is_key and "PretestKey" or "PretestHint",
        }
        col = col + #text
      end
    end
    lines[#lines + 1] = table.concat(parts)
  end
  return lines, marks
end

function M.setup()
  if highlights_setup then
    return
  end
  highlights_setup = true
  apply_highlights()
  local group = vim.api.nvim_create_augroup("pretest_highlights", { clear = true })
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
end

---@class pretest.HeaderLayout
---@field name_row integer
---@field limits_row integer
---@field sep_row integer
---@field cases_label_row integer
---@field cases_start integer
---@field hint_base integer|nil
---@field min_height integer
---@field show_hints boolean
---@field n integer

---@param n integer
---@param hint_n integer|nil
---@return pretest.HeaderLayout
local function header_layout(n, hint_n)
  local show_hints = get_show_hints()
  if hint_n == nil then
    hint_n = show_hints and #HINT_SEGMENTS or 0
  end
  local name_row = 0
  local limits_row = 1
  local sep_row = 2
  -- name, limits, sep, "Testcases AC/total", then cases
  local cases_label_row = 3
  local cases_start = 4
  -- blank after cases only when hints follow
  local hint_base = show_hints and (cases_start + n + 1) or nil
  -- name + limits + sep + label + cases + optional (blank + hints)
  local min_height = math.min(HEADER_HEIGHT_CAP, math.max(4, 4 + n + (show_hints and (1 + hint_n) or 0)))
  return {
    name_row = name_row,
    limits_row = limits_row,
    sep_row = sep_row,
    cases_label_row = cases_label_row,
    cases_start = cases_start,
    hint_base = hint_base,
    min_height = min_height,
    show_hints = show_hints,
    n = n,
  }
end

---@param n integer
---@return integer
local function header_content_min(n)
  -- Unwrapped hint rows only; wrapping must not change section heights.
  return header_layout(n).min_height
end

local CASES_LABEL = "Testcases "

---@return integer ac
---@return integer total
---@return string hl
local function ac_summary()
  local total = (session and session.problem and #session.problem.tests) or 0
  local ac, has_fail, has_running = 0, false, false
  if session then
    for i = 1, total do
      local v = session.results[i] and session.results[i].verdict
      if v == "AC" then
        ac = ac + 1
      elseif v == "Running" then
        has_running = true
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
  else
    hl = "PretestPending"
  end
  return ac, total, hl
end

---@return string
local function format_cases_label()
  local ac, total = ac_summary()
  return CASES_LABEL .. string.format("%d/%d", ac, total)
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
  elseif verdict == "CE" then
    return "PretestCE"
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
  local num
  if i == idx then
    num = string.format("[%s]", string.format("%" .. width .. "d", i))
  else
    num = string.format(" %s ", string.format("%" .. width .. "d", i))
  end

  local verdict = result and result.verdict or nil
  local show = verdict and verdict ~= "Pending"
  if not show then
    return num, 0, #num, nil, nil, verdict_hl(verdict)
  end

  -- Pad so time always starts at the same column (longest shown: "Running").
  local VERDICT_WIDTH = 7
  local verdict_s = string.format("%-" .. VERDICT_WIDTH .. "s", verdict)
  local time_s = result.time_ms and string.format(" %.0fms", result.time_ms) or ""
  local line = num .. " " .. verdict_s .. time_s
  local vcol = #num + 1
  return line, 0, #num, vcol, vcol + #verdict, verdict_hl(verdict)
end

---@param buf integer
---@param layout pretest.HeaderLayout
---@param idx integer
---@param hint_marks { row: integer, col: integer, end_col: integer, hl: string }[]
local function apply_header_marks(buf, layout, idx, hint_marks)
  vim.api.nvim_buf_clear_namespace(buf, HEADER_NS, 0, -1)

  local sep_line = vim.api.nvim_buf_get_lines(buf, layout.sep_row, layout.sep_row + 1, false)[1] or ""
  if sep_line ~= "" then
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.sep_row, 0, {
      end_col = #sep_line,
      hl_group = "PretestSep",
    })
  end

  local limits_line = vim.api.nvim_buf_get_lines(buf, layout.limits_row, layout.limits_row + 1, false)[1] or ""
  local bar_col = limits_line:find("│", 1, true)
  if bar_col then
    -- find() returns 1-based byte index of the first byte of │
    local bar_start = bar_col - 1
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.limits_row, bar_start, {
      end_col = bar_start + #"│",
      hl_group = "PretestSep",
    })
  end

  local label_line = vim.api.nvim_buf_get_lines(buf, layout.cases_label_row, layout.cases_label_row + 1, false)[1] or ""
  if #label_line > #CASES_LABEL then
    local _, _, summary_hl = ac_summary()
    vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.cases_label_row, #CASES_LABEL, {
      end_col = #label_line,
      hl_group = summary_hl,
    })
  end

  local n = layout.n
  for i = 1, n do
    local row = layout.cases_start + i - 1
    local result = session.results[i]
    local line, num_col, num_end, vcol, vend, hl = format_case_line(i, n, idx, result)
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
      vim.api.nvim_buf_set_extmark(buf, HEADER_NS, row, num_col, {
        end_col = #line,
        hl_group = hl,
      })
    end
  end

  if layout.hint_base and hint_marks then
    for _, m in ipairs(hint_marks) do
      vim.api.nvim_buf_set_extmark(buf, HEADER_NS, layout.hint_base + m.row, m.col, {
        end_col = m.end_col,
        hl_group = m.hl,
      })
    end
  end
end

function M.get_session()
  return session
end

function M.is_open()
  if not session then
    return false
  end
  for _, win in ipairs(session.winids) do
    if valid_win(win) then
      return true
    end
  end
  return false
end

function M.close()
  if not session then
    return
  end
  M.flush_edits()
  clear_ui_modified()
  for _, win in ipairs(session.winids) do
    if valid_win(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  session.winids = {}
  session.main_win = nil
end

function M.flush_edits()
  if not session or not session.problem or #session.problem.tests == 0 then
    return
  end
  local tc = session.problem.tests[session.index]
  if not tc then
    return
  end
  if valid_buf(session.bufs.input) then
    local lines = vim.api.nvim_buf_get_lines(session.bufs.input, 0, -1, false)
    tc.input = util.join_lines(lines)
  end
  if valid_buf(session.bufs.expected) then
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

---@param show_stderr boolean
---@param stderr_h integer|nil
---@return table<string, integer>
local function compute_float_heights(show_stderr, stderr_h)
  local cfg = config.get()
  local n_sections = show_stderr and 5 or 4
  local border = 2
  local total_outer = resolved_float_height()
  stderr_h = show_stderr and math.max(1, stderr_h or 2) or 0
  local content_budget = math.max(12, total_outer - n_sections * border - stderr_h)
  local header, input, expected, output = section_heights_from_weights(content_budget, cfg.float_sections)

  return {
    header = header,
    input = input,
    expected = expected,
    output = output,
    stderr = stderr_h,
    total_outer = total_outer,
  }
end

---Apply weighted heights to sidebar header + body windows.
---@param stderr_h integer
local function apply_sidebar_section_heights(stderr_h)
  if not session then
    return
  end
  local total = 0
  local wins = {}
  for _, win in ipairs(session.winids) do
    if valid_win(win) then
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
  local remaining = math.max(12, total - stderr_h)
  local header_h, input_h, expected_h, output_h =
    section_heights_from_weights(remaining, config.get().sidebar_sections)
  local hmin = header_content_min(#session.problem.tests)
  if header_h < hmin and remaining >= hmin + 9 then
    header_h = hmin
    local body_budget = remaining - header_h
    local sec = config.get().sidebar_sections or {}
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
    if valid_win(win) and vim.api.nvim_win_get_buf(win) == buf then
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
  if not valid_win(win) or vim.api.nvim_win_get_buf(win) ~= session.bufs.header then
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
  for _, key in ipairs({ "header", "input", "expected", "output", "stderr" }) do
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

---Rebuild header buffer (name, cases, wrapped hints, separator).
local function write_header()
  if not session or not valid_buf(session.bufs.header) then
    return
  end
  local n = #session.problem.tests
  local idx = session.index
  local width = header_sep_width()
  local hint_lines, hint_marks = {}, {}
  if get_show_hints() then
    hint_lines, hint_marks = build_hint_lines(width)
  end
  local layout = header_layout(n, #hint_lines)
  local tl = session.problem.timeLimit or config.get().default_time_limit
  local ml = session.problem.memoryLimit or config.get().default_memory_limit

  local header = {
    string.format("%s", session.problem.name or "Pretest"),
    string.format("TL %dms │ ML %dMB", tl, ml),
    header_sep_line(),
    format_cases_label(),
  }
  for i = 1, n do
    local line = format_case_line(i, n, idx, session.results[i])
    header[#header + 1] = line
  end
  if layout.show_hints then
    header[#header + 1] = ""
    for _, line in ipairs(hint_lines) do
      header[#header + 1] = line
    end
  end

  set_lines(session.bufs.header, header)
  vim.bo[session.bufs.header].modifiable = false
  vim.bo[session.bufs.header].modified = false
  apply_header_marks(session.bufs.header, layout, idx, hint_marks)
end

local function prune_winids()
  if not session then
    return
  end
  local kept = {}
  for _, win in ipairs(session.winids) do
    if valid_win(win) then
      table.insert(kept, win)
    end
  end
  session.winids = kept
end

---@param height integer
---@param width integer
---@param row integer
---@param col integer
---@return integer
local function ensure_float_stderr_win(height, width, row, col)
  local win = find_win_for_buf(session.bufs.stderr)
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
  win = vim.api.nvim_open_win(session.bufs.stderr, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Stderr ",
    title_pos = "center",
    zindex = 55,
  })
  configure_win(win, "body")
  table.insert(session.winids, win)
  return win
end

local function hide_float_stderr_win()
  local win = find_win_for_buf(session.bufs.stderr)
  if win then
    pcall(vim.api.nvim_win_close, win, true)
    prune_winids()
  end
end

---@param height integer
---@return integer|nil
local function ensure_sidebar_stderr_win(height)
  local win = find_win_for_buf(session.bufs.stderr)
  if win then
    pcall(vim.api.nvim_win_set_height, win, height)
    set_winbar(win, "Stderr")
    return win
  end
  local out_win = find_win_for_buf(session.bufs.output)
  if not out_win then
    return nil
  end
  local prev = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(out_win)
  vim.cmd("belowright split")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, session.bufs.stderr)
  configure_win(win, "body")
  pcall(vim.api.nvim_win_set_height, win, height)
  set_winbar(win, "Stderr")
  table.insert(session.winids, win)
  if valid_win(prev) then
    pcall(vim.api.nvim_set_current_win, prev)
  end
  return win
end

local function hide_sidebar_stderr_win()
  local win = find_win_for_buf(session.bufs.stderr)
  if win then
    pcall(vim.api.nvim_win_close, win, true)
    prune_winids()
  end
end

local function apply_float_layout(err_lines)
  if not session or session.ui_mode ~= "float" then
    return
  end
  local width = resolved_float_width()
  local show_stderr = err_lines ~= nil
  local stderr_h = show_stderr and math.min(8, #err_lines + 1) or 0
  local heights = compute_float_heights(show_stderr, stderr_h)

  local n_sections = show_stderr and 5 or 4
  local content_h = heights.header + heights.input + heights.expected + heights.output + heights.stderr
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

  if show_stderr then
    ensure_float_stderr_win(heights.stderr, width, y, col)
  else
    hide_float_stderr_win()
  end
end

local function render()
  if not session then
    return
  end
  session.applying = true

  write_header()

  local n = #session.problem.tests
  local idx = session.index
  local result = current_result()
  local verdict = result and result.verdict or "Pending"
  local tc = session.problem.tests[idx]
  local input_lines = tc and util.split_lines(tc.input) or { "" }
  local expected_lines = tc and util.split_lines(tc.output) or { "" }
  local out_lines = result and util.split_lines(result.stdout) or { "" }
  local err_text = ""
  if result and result.stderr and result.stderr ~= "" then
    err_text = result.stderr
  elseif session.compile_stderr and session.compile_stderr ~= "" and verdict == "CE" then
    err_text = session.compile_stderr
  end
  local err_lines = err_text ~= "" and util.split_lines(err_text) or nil

  set_lines(session.bufs.input, input_lines)
  vim.bo[session.bufs.input].modifiable = n > 0

  set_lines(session.bufs.expected, expected_lines)
  vim.bo[session.bufs.expected].modifiable = n > 0

  set_lines(session.bufs.output, out_lines)
  vim.bo[session.bufs.output].modifiable = false

  if err_lines then
    set_lines(session.bufs.stderr, err_lines)
    vim.bo[session.bufs.stderr].modifiable = false
  else
    set_lines(session.bufs.stderr, { "" })
    vim.bo[session.bufs.stderr].modifiable = false
  end

  for _, buf in ipairs({
    session.bufs.input,
    session.bufs.expected,
    session.bufs.output,
    session.bufs.stderr,
  }) do
    apply_empty_eol_marks(buf)
  end

  if session.ui_mode == "sidebar" then
    for _, win in ipairs(session.winids) do
      if valid_win(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if buf == session.bufs.input then
          set_winbar(win, "Input")
        elseif buf == session.bufs.expected then
          set_winbar(win, "Expected")
        elseif buf == session.bufs.output then
          set_winbar(win, "Output")
        elseif buf == session.bufs.header then
          set_winbar(win, "Pretest")
        end
      end
    end

    local stderr_h = 0
    if err_lines then
      stderr_h = math.min(8, #err_lines + 1)
      ensure_sidebar_stderr_win(stderr_h)
    else
      hide_sidebar_stderr_win()
    end
    apply_sidebar_section_heights(stderr_h)
  else
    apply_float_layout(err_lines)
    for _, win in ipairs(session.winids) do
      if valid_win(win) then
        set_winbar(win, "")
      end
    end
  end
  write_header()

  session.applying = false
end

local function map_ui_keys(buf)
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "<C-n>", function()
    M.next_case()
  end, opts)
  vim.keymap.set("n", "<C-p>", function()
    M.prev_case()
  end, opts)
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "R", function()
    require("pretest.commands").run(nil, true)
  end, opts)
  vim.keymap.set("n", "r", function()
    require("pretest.commands").run({ session and session.index }, true)
  end, opts)
  -- <C-R>/<C-r> are identical in terminals; use Ctrl-Shift-r for "all".
  vim.keymap.set("n", "<C-S-r>", function()
    require("pretest.commands").run(nil, false)
  end, opts)
  vim.keymap.set("n", "<C-r>", function()
    require("pretest.commands").run({ session and session.index }, false)
  end, opts)
  vim.keymap.set("n", "<Tab>", function()
    focus_section(1)
  end, opts)
  vim.keymap.set("n", "<S-Tab>", function()
    focus_section(-1)
  end, opts)
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
        util.notify("saved")
      end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      buffer = buf,
      callback = function()
        apply_empty_eol_marks(buf)
      end,
    })
    map_ui_keys(buf)
  end
  for _, buf in ipairs({ session.bufs.header, session.bufs.output, session.bufs.stderr }) do
    map_ui_keys(buf)
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
      M.flush_edits()
      session.index = index
      render()
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
      write_header()
      local width = vim.api.nvim_win_get_width(header_win)
      if width == last_header_wrap_width then
        return
      end
      last_header_wrap_width = width
      session.applying = true
      if session.ui_mode == "sidebar" then
        local stderr_h = 0
        local sw = find_win_for_buf(session.bufs.stderr)
        if sw then
          stderr_h = vim.api.nvim_win_get_height(sw)
        end
        apply_sidebar_section_heights(stderr_h)
      else
        local err_lines = nil
        if find_win_for_buf(session.bufs.stderr) then
          err_lines = vim.api.nvim_buf_get_lines(session.bufs.stderr, 0, -1, false)
        end
        apply_float_layout(err_lines)
      end
      session.applying = false
    end,
  })
end

local function open_sidebar_column()
  vim.cmd("botright vsplit")
  local root = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(root, resolved_sidebar_width())
  vim.api.nvim_win_set_buf(root, session.bufs.header)
  configure_win(root, "header")
  session.main_win = root
  table.insert(session.winids, root)

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
    table.insert(session.winids, win)
  end

  apply_sidebar_section_heights(0)
end

local function open_float_stack()
  local width = resolved_float_width()
  -- Stderr float is created later in apply_float_layout only when non-empty.
  local heights = compute_float_heights(false, 0)
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
    if i == 1 then
      session.main_win = win
    end
    table.insert(session.winids, win)
    y = y + h + 2
  end
end

local function open_layout(mode)
  session.ui_mode = mode
  session.winids = {}
  if mode == "float" then
    open_float_stack()
  else
    open_sidebar_column()
  end
end

---@param src_path string
---@return { results: table<integer, pretest.CaseResult>, index: integer, compile_stderr: string }, boolean
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
    if #problem.tests == 0 then
      session.index = 0
    else
      session.index = 1
    end
  end
end

---@param bufnr integer
---@return boolean
local function is_transient_buf(bufnr)
  if is_ui_buf(bufnr) then
    return true
  end
  local win = vim.api.nvim_get_current_win()
  if valid_win(win) then
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative and cfg.relative ~= "" then
      return true
    end
  end
  local bt = vim.bo[bufnr].buftype
  return bt ~= ""
end

follow_visible_source = function()
  if not session or not M.is_open() or session.applying then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if is_transient_buf(bufnr) then
    return
  end
  local path, ft = util.source_from_buf(bufnr)
  if not path or not util.supported_filetype(ft) then
    M.close()
    return
  end
  local abs = util.abspath(path)
  if session.src_path == abs then
    session.src_bufnr = bufnr
    session.filetype = ft
    return
  end
  switch_source(bufnr, abs, ft)
  render()
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
  if not path then
    util.notify("no file in current buffer", vim.log.levels.ERROR)
    return nil
  end
  if not util.supported_filetype(ft) then
    util.notify("unsupported filetype: " .. tostring(ft), vim.log.levels.ERROR)
    return nil
  end

  local abs = util.abspath(path)
  -- Reuse existing session for the same source even when UI is closed,
  -- so ui_mode / results survive toggle/close.
  if session and session.src_path == abs then
    session.src_bufnr = src_bufnr
    session.filetype = ft
    return session
  end

  if session then
    local was_open = M.is_open()
    switch_source(src_bufnr, abs, ft)
    if was_open then
      render()
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
    bufs = {
      header = make_buf("pretest://header", false),
      input = make_buf("pretest://input", true),
      expected = make_buf("pretest://expected", true),
      output = make_buf("pretest://output", false),
      stderr = make_buf("pretest://stderr", false),
    },
    main_win = nil,
    applying = false,
    compile_stderr = "",
  }
  if #problem.tests == 0 then
    session.index = 0
  else
    session.index = 1
  end
  return session
end

function M.show()
  local s = M.ensure_session()
  if not s then
    return
  end
  if M.is_open() then
    for _, win in ipairs(session.winids) do
      if valid_win(win) and vim.api.nvim_win_get_buf(win) == session.bufs.input then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
    return
  end
  open_layout(session.ui_mode)
  setup_buf_autocmds()
  render()
  for _, win in ipairs(session.winids) do
    if valid_win(win) and vim.api.nvim_win_get_buf(win) == session.bufs.input then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.show()
  end
end

function M.toggle_layout()
  local s = M.ensure_session()
  if not s then
    return
  end
  M.flush_edits()
  local next_mode = session.ui_mode == "sidebar" and "float" or "sidebar"
  set_preferred_ui(next_mode)
  if M.is_open() then
    M.close()
    session.ui_mode = next_mode
    open_layout(next_mode)
    setup_buf_autocmds()
    render()
  else
    session.ui_mode = next_mode
    util.notify("UI mode: " .. next_mode)
  end
end

function M.toggle_hints()
  set_show_hints(not get_show_hints())
  if M.is_open() then
    render()
  end
end

function M.next_case()
  if not session or #session.problem.tests == 0 then
    return
  end
  M.flush_edits()
  session.index = session.index % #session.problem.tests + 1
  render()
  sync_header_cursor()
end

function M.prev_case()
  if not session or #session.problem.tests == 0 then
    return
  end
  M.flush_edits()
  session.index = session.index - 1
  if session.index < 1 then
    session.index = #session.problem.tests
  end
  render()
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
  if #session.problem.tests == 0 then
    util.notify("no testcases", vim.log.levels.WARN)
    return
  end
  index = index or session.index
  if index < 1 or index > #session.problem.tests then
    util.notify("invalid testcase index", vim.log.levels.ERROR)
    return
  end
  M.flush_edits()
  session.index = index
  render()
  for _, win in ipairs(session.winids) do
    if valid_win(win) and vim.api.nvim_win_get_buf(win) == session.bufs.input then
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
  prob.add_testcase(session.problem)
  session.index = #session.problem.tests
  session.results[session.index] = nil
  prob.save(session.problem, session.prob_path)
  if not M.is_open() then
    M.show()
  else
    render()
  end
end

function M.edit_limits()
  local s = M.ensure_session()
  if not s then
    return
  end
  local cfg = config.get()
  local cur_tl = session.problem.timeLimit or cfg.default_time_limit
  local cur_ml = session.problem.memoryLimit or cfg.default_memory_limit

  local function parse_positive_int(val, label)
    local n = tonumber(val)
    if not n or n ~= math.floor(n) or n <= 0 then
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
    vim.ui.input({ prompt = "Memory limit (MB): ", default = tostring(cur_ml) }, function(mem_s)
      if mem_s == nil then
        return
      end
      local mem_n = parse_positive_int(mem_s, "memory limit")
      if not mem_n then
        return
      end
      session.problem.timeLimit = time_n
      session.problem.memoryLimit = mem_n
      prob.save(session.problem, session.prob_path)
      if M.is_open() then
        render()
      end
      util.notify(string.format("limits: %dms / %dMB", time_n, mem_n))
    end)
  end)
end

function M.edit_name()
  local s = M.ensure_session()
  if not s then
    return
  end
  local cur = session.problem.name or "Pretest"

  vim.ui.input({ prompt = "Problem name: ", default = cur }, function(name_s)
    if name_s == nil then
      return
    end
    local name = vim.trim(name_s:gsub("%s+", " "))
    if name == "" then
      util.notify("invalid problem name", vim.log.levels.ERROR)
      return
    end
    session.problem.name = name
    prob.save(session.problem, session.prob_path)
    if M.is_open() then
      render()
    end
    util.notify("name: " .. name)
  end)
end

---@param index integer|nil
function M.delete_testcase(index)
  local s = M.ensure_session()
  if not s then
    return
  end
  if #session.problem.tests == 0 then
    util.notify("no testcases", vim.log.levels.WARN)
    return
  end
  index = index or session.index
  M.flush_edits()
  if not prob.delete_testcase(session.problem, index) then
    util.notify("invalid testcase index", vim.log.levels.ERROR)
    return
  end
  session.results = {}
  if #session.problem.tests == 0 then
    session.index = 0
  else
    session.index = math.min(index, #session.problem.tests)
  end
  prob.save(session.problem, session.prob_path)
  if M.is_open() then
    render()
  end
end

---@param indices integer[]|nil
---@param do_compile boolean
function M.run(indices, do_compile)
  local s = M.ensure_session()
  if not s then
    return
  end
  if #session.problem.tests == 0 then
    util.notify("no testcases — use :Pretest add", vim.log.levels.WARN)
    return
  end
  if vim.api.nvim_buf_is_valid(session.src_bufnr) and vim.bo[session.src_bufnr].modified then
    vim.api.nvim_buf_call(session.src_bufnr, function()
      vim.cmd("write")
    end)
  end
  M.flush_edits()
  if not M.is_open() then
    M.show()
  end

  session.compile_stderr = ""
  local targets = indices
  if not targets or #targets == 0 then
    targets = {}
    for i = 1, #session.problem.tests do
      targets[#targets + 1] = i
    end
  end
  for _, i in ipairs(targets) do
    session.results[i] = {
      verdict = "Pending",
      stdout = "",
      stderr = "",
    }
  end
  render()

  local run_src = session.src_path
  runner.run_tests(session.src_path, session.filetype, session.problem, targets, do_compile, {
    on_compile_start = function()
      local st = state_for(run_src)
      st.compile_stderr = ""
    end,
    on_compile_done = function(ok, stderr)
      local st, live = state_for(run_src)
      if not ok then
        st.compile_stderr = stderr
        util.notify("compile failed", vim.log.levels.ERROR)
        if live then
          render()
        end
      end
    end,
    on_case_start = function(i)
      local st, live = state_for(run_src)
      st.results[i] = {
        verdict = "Running",
        stdout = "",
        stderr = "",
      }
      if live then
        render()
      end
    end,
    on_case_done = function(i, result)
      local st, live = state_for(run_src)
      st.results[i] = result
      if live then
        render()
      end
    end,
    on_all_done = function()
      local st, live = state_for(run_src)
      if live then
        render()
      end
      local ac, total = 0, #targets
      for _, i in ipairs(targets) do
        local r = st.results[i]
        if r and r.verdict == "AC" then
          ac = ac + 1
        end
      end
      util.notify(string.format("done: %d/%d AC", ac, total))
    end,
  })
end

function M.refresh()
  if session and M.is_open() then
    render()
  end
end

local function focus_input_win()
  if not session then
    return
  end
  for _, win in ipairs(session.winids) do
    if valid_win(win) and vim.api.nvim_win_get_buf(win) == session.bufs.input then
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
    render()
    focus_input_win()
    return
  end
  open_layout(session.ui_mode)
  setup_buf_autocmds()
  render()
  focus_input_win()
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
      if valid_win(win) and not is_ui_buf(vim.api.nvim_win_get_buf(win)) then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end
  focus_non_ui_win()
  vim.cmd.edit(vim.fn.fnameescape(src_path))
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
    if b ~= bufnr and vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == old_name then
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
    if not old_src then
      util.notify("no file in current buffer", vim.log.levels.ERROR)
      return
    end
    if not util.supported_filetype(ft) then
      util.notify("unsupported filetype: " .. tostring(ft), vim.log.levels.ERROR)
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

  local live = session and session.src_path == old_src
  if live then
    M.flush_edits()
  end

  if valid_buf(bufnr) then
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

  if live then
    session.applying = true
  end

  local function finish_applying()
    if session then
      session.applying = false
    end
  end

  if vim.fn.rename(old_src, new_src) ~= 0 then
    finish_applying()
    util.notify("failed to move " .. old_src .. " → " .. new_src, vim.log.levels.ERROR)
    return
  end

  if valid_buf(bufnr) then
    local old_name = vim.api.nvim_buf_get_name(bufnr)
    pcall(vim.api.nvim_buf_set_name, bufnr, new_src)
    wipe_leftover_buf(bufnr, old_name)
  end

  local problem = live and session.problem or nil
  local relocated, new_ppath, err = prob.relocate(old_src, new_src, problem)
  runner.relocate_bin(old_src, new_src, ft, new_ft)

  if live then
    if parked[old_src] then
      parked[new_src] = parked[old_src]
      parked[old_src] = nil
    end
    session.src_path = new_src
    if valid_buf(bufnr) then
      session.src_bufnr = bufnr
    end
    session.filetype = new_ft
    session.prob_path = new_ppath
    if relocated then
      session.problem = relocated
    elseif session.problem then
      session.problem.srcPath = new_src
    end
  end

  finish_applying()
  if live and M.is_open() then
    render()
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
