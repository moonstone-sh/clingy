-- Configure package search paths
package.path = "./src/?.lua;./src/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local h = require("tests.harness")

local suites = {
  "tests.invariants.inv_01_02_owner_inherit_spec",
  "tests.invariants.inv_03_07_grammar_modes_spec",
  "tests.invariants.inv_04_05_06_valua_cardinality_spec",
  "tests.invariants.inv_08_short_clusters_spec",
  "tests.invariants.inv_09_10_11_segment_routing_spec",
  "tests.invariants.inv_12_conflict_shadowing_spec",
  "tests.invariants.inv_13_ambiguous_grammar_spec",
  "tests.invariants.inv_14_15_passthrough_spec",
  "tests.invariants.inv_16_typed_context_spec",
  "tests.invariants.inv_17_18_lifecycle_process_spec",
  "tests.invariants.inv_19_signals_spec",
  "tests.invariants.inv_20_21_composer_plain_spec",
  "tests.invariants.inv_22_control_ipc_spec",
  "tests.invariants.inv_23_deterministic_unwind_spec",
  "tests.invariants.inv_24_ndjson_event_parity_spec",
  "tests.invariants.inv_leading_exact_spec",
  "tests.invariants.inv_cluster_atomic_spec",
  "tests.invariants.inv_valua_matrix_spec",
  "tests.invariants.inv_signals_escalation_spec",
  "tests.invariants.inv_help_generation_spec",
  "tests.substrate.composer_synthetic_spec",
  "tests.dsl.dsl_spec",
  "tests.graph.snapshots_spec",
  "tests.properties.parser_properties_spec",
  "tests.luals.binding_identity_spec",
  "tests.luals.modular_assembly_spec",
  "tests.luals.plugin_spec",
  "tests.integration.standard_schema_decoupling_spec",
  "tests.integration.e2e_cli_spec",
}

print("=========================================================")
print("Running Clingy v0 Complete Test Suite (24 Invariants)")
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
