-- Configure package search paths
package.path = "./src/?.lua;./src/?/init.lua;./?.lua;./?/init.lua;./.moonstone/env/share/lua/5.4/?.lua;./.moonstone/env/share/lua/5.4/?/init.lua;" .. package.path

local h = require("tests.harness")

-- This runner is the executable contract for table declarations, forms, and
-- completion behavior.
local suites = {
  "tests.new_api_spec",
  "tests.router_semantics_spec",
  "tests.cli.init_spec",
  "tests.completion.backends_spec",
  "tests.invariants.inv_17_18_lifecycle_process_spec",
  "tests.invariants.inv_19_signals_spec",
  "tests.invariants.inv_20_21_composer_plain_spec",
  "tests.invariants.inv_22_control_ipc_spec",
  "tests.invariants.inv_23_deterministic_unwind_spec",
  "tests.invariants.inv_signals_escalation_spec",
  "tests.presentation.composer_host_spec",
  "tests.presentation.custom_host_spec",
  "tests.presentation.error_containment_spec",
  "tests.presentation.event_ingestion_spec",
  "tests.presentation.performance_spec",
  "tests.presentation.prompt_protocol_spec",
  "tests.presentation.scope_deferral_spec",
  "tests.presentation.signals_handoff_spec",
  "tests.presentation.subprocess_handoff_spec",
  "tests.presentation.test_hosts_spec",
  "tests.substrate.composer_synthetic_spec",
}

print("=========================================================")
print("Running Clingy table-form API test suite")
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
