-- Declare, compile and run in one process (c.create).
local c = require("clingy")
os.exit(c.create(require("greet.cli")):run(arg))
