local ui = require("pretest.ui")
local util = require("pretest.util")

local M = {}

local subcommands = {
  "toggle_layout",
  "run",
  "run_current",
  "run_current_no_compile",
  "run_no_compile",
  "stop",
  "add",
  "edit",
  "delete",
  "copy",
  "paste",
  "edit_limits",
  "edit_name",
  "rename",
  "move",
  "receive",
}

local receive_subcommands = {
  "problem",
  "contest",
  "persistently",
  "stop",
  "status",
}

---Parse 1-based indices from non-empty string args.
---@param args string[]
---@param n integer number of testcases (`1..n` valid)
---@return integer[]|nil nil on parse error
local function parse_indices(args, n)
  local out = {}

  for _, s in ipairs(args) do
    local idx = tonumber(s)
    if not idx or idx ~= math.floor(idx) or idx < 1 or idx > n then
      util.notify("invalid index: " .. s, vim.log.levels.ERROR)
      return nil
    end
    out[#out + 1] = idx
  end

  return out
end

---@param args string[]
---@param do_compile boolean
local function run_with_indices(args, do_compile)
  local s = ui.ensure_session()
  if not s then
    return
  end
  local n = #s.problem.tests
  local indices
  if not args or #args == 0 then
    indices = util.all_indices(n)
  else
    indices = parse_indices(args, n)
    if not indices then
      return
    end
  end
  ui.run(indices, do_compile)
end

---@param do_compile boolean
local function run_current(do_compile)
  local s = ui.get_session() or ui.ensure_session()
  if not s then
    return
  end
  local idx = s.index
  if idx < 1 then
    util.notify("no current testcase", vim.log.levels.WARN)
    return
  end
  ui.run({ idx }, do_compile)
end

---Split a `"x` register argument off `args`.
---@param args string[]
---@return string[]|nil rest nil on error
---@return string|nil reg
local function take_register(args)
  local rest, reg = {}, nil

  for _, a in ipairs(args) do
    if a:match('^".$') then
      if reg then
        util.notify("only one register allowed", vim.log.levels.ERROR)
        return nil
      end
      reg = a:sub(2)
    else
      rest[#rest + 1] = a
    end
  end

  return rest, reg
end

---@param args string[]
local function copy(args)
  local rest, reg = take_register(args)

  if not rest then
    return
  end

  local s = ui.ensure_session()
  if not s then
    return
  end

  local indices
  if #rest == 1 and rest[1] == "all" then
    indices = util.all_indices(#s.problem.tests)
  elseif #rest > 0 then
    indices = parse_indices(rest, #s.problem.tests)
    if not indices then
      return
    end
  end

  ui.copy_testcases(indices, reg)
end

---@param args string[]
local function paste(args)
  local rest, reg = take_register(args)
  if not rest then
    return
  end

  if #rest > 0 then
    util.notify('usage: Pretest paste ["x]', vim.log.levels.WARN)
    return
  end

  ui.paste_testcases(reg)
end

---@param args string
function M.command(args)
  local parts = vim.split(args, " ", { plain = true, trimempty = true })
  local sub = parts[1]
  if not sub then
    ui.focus()
  elseif sub == "toggle_layout" then
    ui.toggle_layout()
  elseif sub == "run" then
    run_with_indices(vim.list_slice(parts, 2), true)
  elseif sub == "run_current" then
    run_current(true)
  elseif sub == "run_current_no_compile" then
    run_current(false)
  elseif sub == "run_no_compile" then
    run_with_indices(vim.list_slice(parts, 2), false)
  elseif sub == "stop" then
    ui.stop()
  elseif sub == "add" then
    ui.add_testcase()
  elseif sub == "edit" then
    local idx = tonumber(parts[2])
    ui.goto_case(idx)
  elseif sub == "delete" then
    local idx = tonumber(parts[2])
    ui.delete_testcase(idx)
  elseif sub == "copy" then
    copy(vim.list_slice(parts, 2))
  elseif sub == "paste" then
    paste(vim.list_slice(parts, 2))
  elseif sub == "edit_limits" then
    ui.edit_limits()
  elseif sub == "edit_name" then
    ui.edit_name()
  elseif sub == "rename" then
    local dest = table.concat(vim.list_slice(parts, 2), " ")
    ui.move_source(dest, { relative_to = "src_dir" })
  elseif sub == "move" then
    local dest = table.concat(vim.list_slice(parts, 2), " ")
    ui.move_source(dest, { relative_to = "cwd" })
  elseif sub == "receive" then
    local companion = require("pretest.companion")
    local mode = parts[2]
    if not mode or mode == "testcases" then
      -- "testcases" is an undocumented alias for the default (current file).
      companion.start("current")
    elseif mode == "stop" then
      if companion.stop() then
        util.notify("stopped receiving")
      else
        util.notify("receiving not enabled")
      end
    elseif mode == "status" then
      companion.status()
    elseif mode == "problem" or mode == "contest" or mode == "persistently" then
      companion.start(mode)
    else
      util.notify(
        "usage: Pretest receive [{problem|contest|persistently|stop|status}]",
        vim.log.levels.WARN
      )
    end
  else
    util.notify("unknown subcommand: " .. sub, vim.log.levels.ERROR)
  end
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local parts = vim.split(cmdline, " ", { plain = true, trimempty = true })
  -- cmdline looks like: "Pretest", "Pretest r", "Pretest run 1"
  -- Completing the subcommand when only the command is present (optionally
  -- with a trailing space), or when typing a partial subcommand.
  local completing_sub = (#parts == 1) or (#parts == 2 and not cmdline:match("%s$"))
  if completing_sub then
    local matches = {}
    for _, s in ipairs(subcommands) do
      if s:sub(1, #arglead) == arglead then
        matches[#matches + 1] = s
      end
    end
    return matches
  end

  local completing_path = (parts[2] == "rename" or parts[2] == "move")
    and ((#parts == 2 and cmdline:match("%s$")) or (#parts >= 3 and not cmdline:match("%s$")))
  if completing_path then
    return vim.fn.getcompletion(arglead, "file")
  end

  local completing_copy = parts[2] == "copy"
    and ((#parts == 2 and cmdline:match("%s$")) or (#parts == 3 and not cmdline:match("%s$")))
  if completing_copy then
    return vim.startswith("all", arglead) and { "all" } or {}
  end

  local completing_receive = parts[2] == "receive"
    and ((#parts == 2 and cmdline:match("%s$")) or (#parts == 3 and not cmdline:match("%s$")))
  if completing_receive then
    local matches = {}
    for _, s in ipairs(receive_subcommands) do
      if s:sub(1, #arglead) == arglead then
        matches[#matches + 1] = s
      end
    end
    return matches
  end
  return {}
end

function M.setup()
  vim.api.nvim_create_user_command("Pretest", function(opts)
    M.command(opts.args)
  end, {
    nargs = "*",
    complete = function(arglead, cmdline)
      return M.complete(arglead, cmdline)
    end,
    desc = "Pretest.nvim commands",
  })
end

return M
