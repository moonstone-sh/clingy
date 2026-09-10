local h = require("tests.harness")
local c = require("clingy")
local lifecycle = require("clingy.lifecycle")
local process = require("clingy.process")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 17 & 18: Lifecycle DAG and Managed Process Supervision", function()

  describe("Invariant 17: Lifecycle DAG (Section 28)", function()
    it("executes default stages in topological order", function()
      local dag = lifecycle.create_dag()
      local order = dag:resolve_order()
      local order_ids = {}
      for _, st in ipairs(order) do
        table.insert(order_ids, st.id)
      end

      -- Verify required stages exist and are correctly ordered
      local function index_of(id)
        for i, s_id in ipairs(order_ids) do
          if s_id == id then return i end
        end
        error("Stage not found: " .. id)
      end

      assert.truthy(index_of("bootstrap") < index_of("terminal_detect"))
      assert.truthy(index_of("terminal_detect") < index_of("parse"))
      assert.truthy(index_of("parse") < index_of("route"))
      assert.truthy(index_of("route") < index_of("validate"))
      assert.truthy(index_of("validate") < index_of("prepare"))
      assert.truthy(index_of("prepare") < index_of("dispatch"))
      assert.truthy(index_of("dispatch") < index_of("run"))
    end)

    it("allows inserting custom lifecycle stages with explicit before/after edges", function()
      local dag = lifecycle.create_dag()
      dag:add_stage({
        id = "load_project",
        after = { "validate" },
        before = { "dispatch" },
      })

      local order = dag:resolve_order()
      local validate_idx, load_idx, dispatch_idx

      for i, st in ipairs(order) do
        if st.id == "validate" then validate_idx = i end
        if st.id == "load_project" then load_idx = i end
        if st.id == "dispatch" then dispatch_idx = i end
      end

      assert.truthy(validate_idx < load_idx)
      assert.truthy(load_idx < dispatch_idx)
    end)

    it("detects dependency cycles in lifecycle stages and raises an error", function()
      local dag = lifecycle.create_dag()
      dag:add_stage({ id = "cycle_a", after = { "cycle_b" } })
      dag:add_stage({ id = "cycle_b", after = { "cycle_a" } })

      assert.has_error(function()
        dag:resolve_order()
      end, "Cycle detected")
    end)
  end)

  describe("Invariant 18: Managed Subprocesses & Explicit Lifecycle States (Section 31)", function()
    it("tracks process lifecycle state transitions: declared -> spawning -> running -> reaped", function()
      local state_history = {}

      local proc = process.ManagedProcess.new({
        argv = { "echo", "clingy-subprocess-test" },
      })

      assert.equal(proc:state(), "declared")
      table.insert(state_history, proc:state())

      proc:start()
      -- After start, state is running
      assert.equal(proc:state(), "running")
      table.insert(state_history, proc:state())

      local exit_code, stdout, stderr = proc:wait()
      assert.equal(exit_code, 0)
      assert.matches(stdout, "clingy%-subprocess%-test")

      -- After wait, process must be reaped
      assert.equal(proc:state(), "reaped")
      table.insert(state_history, proc:state())

      assert.same(state_history, { "declared", "running", "reaped" })
    end)

    it("spawns subprocess within CLI handler and reaps it successfully", function()
      local captured_exit = nil
      local captured_out = nil

      local app = c.create({
        name = "test-spawn-cli",
        root = c.node({
          c.run(function(ctx)
            local p = ctx:spawn({
              argv = { "echo", "hello-from-clingy" },
            })
            assert.equal(p:state(), "running")
            local code, out = p:wait()
            captured_exit = code
            captured_out = out
            assert.equal(p:state(), "reaped")
          end),
        }),
      })

      local code = app:run({}, { capture = true })
      assert.equal(code, 0)
      assert.equal(captured_exit, 0)
      assert.matches(captured_out, "hello%-from%-clingy")
    end)

    it("handles process termination state transitions", function()
      local proc = process.ManagedProcess.new({
        argv = { "sleep", "1" },
      })
      proc:start()
      assert.equal(proc:state(), "running")

      proc:terminate()
      assert.equal(proc:state(), "terminating")

      proc:kill(9)
      assert.equal(proc:state(), "killed")
    end)
  end)

end)
