package.path = "./src/?.lua;./src/?/init.lua;../valua/src/?.lua;../valua/src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local function time_fn(name, iterations, fn)
  -- Warmup
  for _ = 1, 100 do fn() end

  local start_time = os.clock()
  for _ = 1, iterations do
    fn()
  end
  local duration = os.clock() - start_time
  local ops_per_sec = math.floor(iterations / (duration > 0 and duration or 0.0001))
  print(string.format("%-35s | %d ops | %7.4f s | %10d ops/s", name, iterations, duration, ops_per_sec))
  return ops_per_sec
end

print("=====================================================================")
print("Clingy v0 Performance Sanity Benchmarks (Section 49)")
print("=====================================================================")

-- Benchmark 1: CLI Compilation
local function make_cli_config()
  return {
    name = "bench",
    version = "1.0.0",
    c.root(c.node({
      c.inherit(
        c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }),
        c.flag({ key = "quiet", aliases = { "-q", "--quiet" } }),
        c.flag({ key = "json", aliases = { "--json" } })
      ),
      deploy = c.node({
        c.arg({ key = "env", schema = v.picklist({ "staging", "prod" }) }),
        c.option({ key = "replicas", aliases = { "-r", "--replicas" }, value = { schema = v.integer() } }),
        c.option({ key = "define", aliases = { "-D", "--define" }, value = { schema = v.string() }, occurs = { min = 0, max = "many" } }),
      }),
      build = c.node({
        c.flag({ key = "force", aliases = { "-f", "--force" } }),
        c.arg({ key = "target", schema = v.string() }),
      }),
    })),
  }
end

time_fn("CLI Compilation (c.create)", 10000, function()
  local app = c.create(make_cli_config())
end)

-- Benchmark 2: Simple Invocation Parsing
local app = c.create(make_cli_config())
local simple_argv = { "build", "-f", "main.lua" }

time_fn("Simple Invocation Parsing", 100000, function()
  local res = app:parse(simple_argv)
end)

-- Benchmark 3: Deep Route with Inherited Flags & Picklists
local deep_argv = { "-v", "--json", "deploy", "prod", "-r", "5", "-D", "FOO=BAR", "-D", "BAZ=QUX" }

time_fn("Deep Route + Picklists + Repeats", 100000, function()
  local res = app:parse(deep_argv)
end)

-- Benchmark 4: Short Flag Clusters
local tar_app = c.create({
  name = "tar",
  c.root(c.node({
    c.short_clusters(),
    c.flag({ key = "extract", aliases = { "-x", "--extract" } }),
    c.flag({ key = "force", aliases = { "-f", "--force" } }),
    c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }),
    c.flag({ key = "gzip", aliases = { "-z", "--gzip" } }),
    c.arg({ key = "archive", schema = v.string() }),
  })),
})
local cluster_argv = { "-xfvz", "bundle.tar.gz" }

time_fn("Short Flag Clusters (-xfvz)", 100000, function()
  local res = tar_app:parse(cluster_argv)
end)

-- Benchmark 5: Ordered Pipeline Parsing
local legacy_app = c.create({
  name = "legacy",
  c.root(c.node({
    c.ordered(),
    c.flag({ key = "prepare", aliases = { "--prepare" } }),
    c.arg({ key = "source", schema = v.string() }),
    c.flag({ key = "commit", aliases = { "--commit" } }),
    c.arg({ key = "destination", schema = v.string() }),
  })),
})
local ordered_argv = { "--prepare", "in.dat", "--commit", "out.dat" }

time_fn("Strict Ordered Pipeline Parsing", 100000, function()
  local res = legacy_app:parse(ordered_argv)
end)

print("=====================================================================")
