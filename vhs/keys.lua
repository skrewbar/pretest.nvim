-- Show recently typed keys in a float, for the VHS recording only.
-- VHS has no keystroke overlay, so the tape sources this after setup.
-- Text typed in Insert / Cmdline mode is joined (`:Pretest`, `2000000000`);
-- Normal-mode keys stay separate, except `<Space>` + key (`<Space>j`) and
-- operator-pending keys (`ciw`).
local CLEAR_MS = 1500
local MAX_WIDTH = 48

local ns = vim.api.nvim_create_namespace("pretest_vhs_keys")
local buf = vim.api.nvim_create_buf(false, true)
local win = nil
---@type { text: string, open: boolean }[]
local segments = {}
local timer = assert(vim.uv.new_timer())

vim.api.nvim_set_hl(0, "PretestVhsKeys", { link = "Title", default = true })

local IGNORED = {
  "^<Mouse",
  "^<.*Mouse>$",
  "^<.*Release>$",
  "^<.*Drag>$",
  "^<Scroll",
  "^<Focus",
  "^<Cursor",
  "^<Ignore>$",
  "^<Nop>$",
  "^<Plug>",
  "^<SNR>",
  "Event>$",
}

---@param key string keytrans() form
---@return boolean
local function ignored(key)
  for _, pat in ipairs(IGNORED) do
    if key:find(pat) then
      return true
    end
  end
  return false
end

local function text()
  local function join()
    local parts = {}
    for _, seg in ipairs(segments) do
      parts[#parts + 1] = seg.text
    end
    return table.concat(parts, "  ")
  end
  -- Keep the newest keys when the line gets too long.
  local s = join()
  while #segments > 1 and vim.fn.strdisplaywidth(s) > MAX_WIDTH do
    table.remove(segments, 1)
    s = join()
  end
  return s
end

local function hide()
  segments = {}
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, { hide = true })
  end
end

local function render()
  local s = " " .. text() .. " "
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { s })
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #s, hl_group = "PretestVhsKeys" })

  local width = vim.fn.strdisplaywidth(s)
  local cfg = {
    relative = "editor",
    anchor = "SW",
    row = vim.o.lines - 3,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 250,
    hide = false,
  }
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, cfg)
  else
    cfg.noautocmd = true
    win = vim.api.nvim_open_win(buf, false, cfg)
    -- Typed search / :s patterns would otherwise match the overlay text too.
    vim.wo[win][0].winhighlight = "Search:None,CurSearch:None,IncSearch:None,Substitute:None"
  end
end

---@param key string keytrans() form
---@param mode string mode() when the key was typed
local function push(key, mode)
  local typing = mode:find("^[icR]") ~= nil
  if typing and key == "<Space>" then
    key = " "
  end
  local plain = vim.fn.strchars(key) == 1
  local pending = mode:find("^no") ~= nil
  local last = segments[#segments]
  if last and plain and (last.open or pending) then
    last.text = last.text .. key
    -- `<Space>j` is one Normal-mode sequence; Insert / Cmdline text keeps going.
    last.open = typing
  else
    -- `:` and `/` start a Cmdline run, `<Space>` a leader sequence.
    local open = (typing and plain) or (not typing and (key == ":" or key == "/" or key == "<Space>"))
    segments[#segments + 1] = { text = key, open = open }
  end
  render()
  timer:stop()
  timer:start(CLEAR_MS, 0, vim.schedule_wrap(hide))
end

local K_SPECIAL = 0x80
local KS_MODIFIER = 0xfc

---Split raw typed bytes into keys: K_SPECIAL sequences take 3 bytes, a
---modifier sequence also takes the key it modifies, anything else is one char.
---@param raw string
---@return string[]
local function split_keys(raw)
  local keys = {}
  local i = 1
  while i <= #raw do
    local j = i
    while raw:byte(j) == K_SPECIAL and raw:byte(j + 1) == KS_MODIFIER do
      j = j + 3
    end
    if raw:byte(j) == K_SPECIAL then
      j = j + 2
    else
      j = j + vim.str_utf_end(raw, j)
    end
    keys[#keys + 1] = raw:sub(i, j)
    i = j + 1
  end
  return keys
end

---Raw keys already shown, newest last (enough to spot a repeated lhs).
---@type string[]
local seen = {}

vim.on_key(function(_, typed)
  -- Only keys the user typed: mappings and plugins (which-key) feed more.
  if not typed or typed == "" then
    return
  end
  local keys = split_keys(typed)
  -- A resolved mapping reports keys again (`<Space>j` after `<Space>`, `j`;
  -- `iw` after `i`), and a pending one reports late with the next key
  -- (`<Tab>4`). Skip the leading keys that were just shown.
  local skip = 0
  if #keys > 1 then
    for n = math.min(#keys, #seen), 1, -1 do
      if table.concat(seen, "", #seen - n + 1) == table.concat(keys, "", 1, n) then
        skip = n
        break
      end
    end
  end
  local mode = vim.fn.mode(1)
  local names = {}
  for i = skip + 1, #keys do
    local k = keys[i]
    seen[#seen + 1] = k
    local name = vim.fn.keytrans(k)
    if name ~= "" and not ignored(name) then
      names[#names + 1] = name
    end
  end
  while #seen > 16 do
    table.remove(seen, 1)
  end
  if #names == 0 then
    return
  end
  -- on_key runs under textlock; draw on the next tick.
  vim.schedule(function()
    for _, name in ipairs(names) do
      push(name, mode)
    end
  end)
end, ns)
