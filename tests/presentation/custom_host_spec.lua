local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Custom Presentation Host Integration (HOST-INV-03, 17)", function()

  it("mounts a custom stateful Presentation Host with custom event processing", function()
    -- Custom TUI-like or dashboard presentation host
    local CustomHost = {}
    CustomHost.__index = CustomHost

    function CustomHost.new()
      return setmetatable({
        rendered_frames = {},
        active_spans = {},
        status = "uninitialized",
      }, CustomHost)
    end

    function CustomHost:start(invocation)
      self.status = "running"
      table.insert(self.rendered_frames, "[START] " .. invocation.app_name)
    end

    function CustomHost:handle_event(evt)
      if evt.type == "span_start" then
        self.active_spans[evt.span_id] = evt.name
        table.insert(self.rendered_frames, "[SPAN+] " .. evt.name)
      elseif evt.type == "span_end" then
        self.active_spans[evt.span_id] = nil
        table.insert(self.rendered_frames, "[SPAN-] " .. evt.name .. " (" .. evt.status .. ")")
      elseif evt.type == "log" then
        table.insert(self.rendered_frames, "[LOG:" .. evt.level .. "] " .. evt.message)
      elseif evt.type == "result" then
        table.insert(self.rendered_frames, "[RESULT] " .. tostring(evt.data and evt.data.summary or evt.data))
      end
    end

    function CustomHost:flush() end
    function CustomHost:suspend(reason) end
    function CustomHost:resume() end
    function CustomHost:prompt(request) return request.default end

    function CustomHost:finish(result)
      self.status = "finished"
      table.insert(self.rendered_frames, "[FINISH:" .. result.status .. "] exit=" .. tostring(result.exit_code))
    end

    function CustomHost:close()
      self.status = "closed"
      table.insert(self.rendered_frames, "[CLOSED]")
    end

    local my_host = CustomHost.new()
    local app = c.create({
      name = "custom-dashboard",
      presentation = my_host,
      root = c.node({
        c.run(function(ctx)
          ctx:span("compilation", function()
            ctx:log("info", "Compiling kernel")
          end)
          ctx:result({ summary = "Kernel built successfully" })
        end),
      }),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.equal(my_host.status, "closed")

    local history = table.concat(my_host.rendered_frames, "\n")
    assert.truthy(history:find("%[START%] custom%-dashboard"))
    assert.truthy(history:find("%[SPAN%+%] compilation"))
    assert.truthy(history:find("%[LOG:info%] Compiling kernel"))
    assert.truthy(history:find("%[SPAN%-%] compilation %(ok%)"))
    assert.truthy(history:find("%[RESULT%] Kernel built successfully"))
    assert.truthy(history:find("%[FINISH:ok%] exit=0"))
    assert.truthy(history:find("%[CLOSED%]"))
  end)

  it("supports minimal table with only handle_event method", function()
    local events_received = {}
    local minimal_host = {
      handle_event = function(self, evt)
        table.insert(events_received, evt.type)
      end,
    }

    local app = c.create({
      name = "minimal-host-app",
      presentation = minimal_host,
      root = c.node({
        c.run(function(ctx)
          ctx:log("info", "Minimal message")
          return "done"
        end),
      }),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.truthy(#events_received > 0)
    assert.truthy(h.contains(events_received, "log"))
    assert.truthy(h.contains(events_received, "invocation_start"))
    assert.truthy(h.contains(events_received, "invocation_finish"))
  end)

end)
