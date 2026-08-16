local ui = require("pretest.ui")
local util = require("pretest.util")

local M = {}

local subcommands = {
  "toggle",
  "toggle_layout",
  "toggle_hints",
  "run",
  "run_current",
  "run_no_compile",
  "stop",
  "add",
  "edit",
  "delete",
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
---@return integer[]|nil nil on parse error
local function parse_indices(args)
  local out = {}
  for _, s in ipairs(args) do
    local n = tonumber(s)
    if not n then
      util.notify("invalid index: " .. s, vim.log.levels.ERROR)
      return nil
    end
    out[#out + 1] = n
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
  local indices
  if not args or #args == 0 then
    indices = util.all_indices(#s.problem.tests)
  else
    indices = parse_indices(args)
    if not indices then
      return
    end
  end
  ui.run(indices, do_compile)
end

---@param args string
function M.command(args)
  local parts = vim.split(args, " ", { plain = true, trimempty = true })
  local sub = parts[1]
  if not sub then
    util.notify("usage: Pretest <subcommand>", vim.log.levels.WARN)
    return
  end

  if sub == "toggle" then
    ui.toggle()
  elseif sub == "toggle_layout" then
    ui.toggle_layout()
  elseif sub == "toggle_hints" then
    ui.toggle_hints()
  elseif sub == "run" then
    run_with_indices(vim.list_slice(parts, 2), true)
  elseif sub == "run_current" then
    local s = ui.get_session() or ui.ensure_session()
    if not s then
      return
    end
    local idx = s.index
    if idx < 1 then
      util.notify("no current testcase", vim.log.levels.WARN)
      return
    end
    ui.run({ idx }, true)
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
