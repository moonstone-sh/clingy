-- Configure package search paths
package.path = "./src/?.lua;./src/?/init.lua;./?.lua;./?/init.lua;./.moonstone/env/share/lua/5.4/?.lua;./.moonstone/env/share/lua/5.4/?/init.lua;" .. package.path

local h = require("tests.harness")

-- v0.3 is a deliberate DSL break.  The old invariant suite specifies removed
-- declaration wrappers and is retained only as historical reference; this
-- runner is the executable contract for table declarations and forms.
local suites = { "tests.new_api_spec" }

print("=========================================================")
print("Running Clingy v0.3 table-form API test suite")
print("=========================================================")

for _, suite_name in ipairs(suites) do
  local ok, err = pcall(require, suite_name)
  if not ok then
    h.failed = h.failed + 1
    table.insert(h.errors, string.format("FAILED TO LOAD SUITE '%s':\n  %s", suite_name, tostring(err)))
    print(string.format("  ✗ FAILED TO LOAD %s: %s", suite_name, tostring(err)))
  end
end

print("\n=========================================================")
print(string.format("Test Results: %d Passed, %d Failed", h.passed, h.failed))
print("=========================================================")

if h.failed > 0 then
  print("\nFailures:")
  for _, err in ipairs(h.errors) do
    print(err)
  end
  os.exit(1)
else
  print("All test suites passed successfully!")
  os.exit(0)
end
