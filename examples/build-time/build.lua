-- Writes greet/built.lua (the CLI) and greet/built/args.lua (typed keys).
os.execute("mkdir -p greet/built")
require("clingy.build").write({ declaration = "greet.cli", module = "greet.built" })
print("built greet/built.lua and greet/built/args.lua")
