package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

require("tests.pure_spec")
require("tests.helpers").run()
