-- Seed a demo .prob for the current buffer using the user's pretest config.
-- Invoked with nvim --headless -S (waits for LazyVim).
local done = false

local function seed()
  if done then
    return
  end
  done = true

  vim.bo.filetype = "cpp"

  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.load({ plugins = { "pretest.nvim" } })
  end

  local prob = require("pretest.prob")
  local runner = require("pretest.runner")
  local src = vim.api.nvim_buf_get_name(0)
  if src == "" then
    error("pretest vhs seed: current buffer has no name")
  end

  local problem, path = prob.load_or_create(src)
  problem.name = "A + B"
  problem.group = "Demo"
  problem.timeLimit = 3000
  problem.memoryLimit = 256
  -- The tape adds a third case that overflows `int`, then fixes the source.
  problem.tests = {
    { id = 1, input = "1 2\n", output = "3\n" },
    { id = 2, input = "10 20\n", output = "30\n" },
  }

  if not path then
    path = prob.prob_path(src)
  end
  if not path or not prob.save(problem, path) then
    error("pretest vhs seed: failed to write .prob")
  end

  local dir = vim.fn.fnamemodify(src, ":h")
  local artifacts = { path, runner.bin_path_for(src) }
  local f, err = io.open(dir .. "/.vhs-cleanup", "w")
  if not f then
    error("pretest vhs seed: failed to write cleanup list: " .. tostring(err))
  end
  for _, p in ipairs(artifacts) do
    f:write(p .. "\n")
  end
  f:close()

  vim.cmd("qa!")
end

vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = seed,
})
vim.defer_fn(seed, 4000)
