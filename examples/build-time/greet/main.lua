-- Entry of the built CLI: no declaration, DSL, or schema library.
local runtime = require("clingy.runtime")
local built = require("greet.built")
return function(argv) return runtime.run(built, argv) end
