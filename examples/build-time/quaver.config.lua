-- quaver build quaver.config.lua greet.bundle.lua (run from this directory)
-- VALUA_SRC points at Valua's src/ directory.
local valua = assert(os.getenv("VALUA_SRC"), "set VALUA_SRC")
return { mode = "strict", format = "bundle", minify = { level = "compact" }, entry = "greet.main",
  roots = { ".", "../../src", valua }, externals = { lfs = true } }
