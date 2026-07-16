package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local h = require("tests.helpers")

h.test("Neovim test harness starts", function()
  h.truthy(vim.api.nvim_get_current_buf() > 0)
end)

h.run()
