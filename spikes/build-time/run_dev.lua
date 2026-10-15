-- Today's path: declare, compile and run in one process.
local c = require("clingy")
local app = c.create(require("greet.cli"))
local code = app:run(arg)
os.exit(code)
