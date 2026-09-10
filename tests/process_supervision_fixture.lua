-- Emit the production supervisor for the black-box process tests.
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local process = require("clingy.process")
local root = assert(arg[1], "fixture root is required")
local argv = {}
for index = 3, #arg do argv[#argv + 1] = arg[index] end

io.write(process.supervisor_script({
  argv = argv,
  cwd = root,
  env = { CLINGY_TEST_LITERAL = "literal $(echo unsafe) `echo unsafe` ' \" $HOME" },
  stdin_eof = arg[2] ~= "disabled",
  grace_ms = 300,
  label = "Clingy process test",
  lock_dir = os.getenv("CLINGY_TEST_LOCK_DIR"),
  cleanup_files = { root .. "/cleanup.marker" },
}))
