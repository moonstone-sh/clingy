local root = assert(os.getenv("CLINGY_TEST_ROOT"))
package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path
require("moonstone.variants").install()
local supervisor = require("clingy.supervisor")
assert(supervisor.extension == ".ps1", "Windows flavor was not selected")
local argv = {}
for index = 3, #arg do argv[#argv + 1] = arg[index] end
local script = supervisor.script({
  argv = argv,
  cwd = os.getenv("CLINGY_TEST_CWD"),
  env = { CLINGY_TEST_VALUE = "literal & % ! ' ü" },
  grace_ms = 200,
  stdin_eof = arg[2] == "eof",
  lock_dir = os.getenv("CLINGY_TEST_LOCK"),
  cleanup_files = { os.getenv("CLINGY_TEST_CLEANUP") or "missing-cleanup-file" },
})
local file = assert(io.open(arg[1], "wb"))
-- Windows PowerShell 5.1 requires BOM to recognize non-ASCII script literals.
file:write("\239\187\191", script)
file:close()
