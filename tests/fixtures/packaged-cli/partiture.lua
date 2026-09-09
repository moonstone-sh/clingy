local ballad = require("ballad")

return ballad.partiture(function(p)
  local moonstone = p:use(ballad.plugins.moonstone)
  local project = moonstone.project({ root = "." })
  local layout = p:use(ballad.plugins.layout)
  local app = layout.exec(project, {
    name = "clingy-example",
    bin = "clingy-example",
    entry = "tests/fixtures/packaged-cli/main.lua",
    interpreter = "lua",
    include = { "src/**", "tests/fixtures/packaged-cli/main.lua" },
  })
  local artifact = moonstone.registry.package(app, {
    name = "moonstone/clingy-example",
    version = project.version,
    target = "any",
    runtime = "lua@5.4",
    lua_abi = "5.4",
    dependencies = {},
  })
  p.sink.artifact(artifact, { out = "dist/registry/clingy-example" })
end)
