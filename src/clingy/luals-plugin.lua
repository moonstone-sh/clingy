--[[
  clingy — LuaLS plugin self-description.

  Read by `moonstone/luals-composer` when a consuming project enrolls clingy by
  name: `require("luals_composer").enroll{ root = ..., plugin = "clingy" }`.
  Composer loads this file as inert data in an empty environment, so it must
  contain nothing but this table.

  Composer looks for it at the root of clingy's INSTALLED Lua module tree
  (`.moonstone/env/share/lua/<abi>/clingy/luals-plugin.lua`), which is where
  this file lands from `src/clingy/`. `path` below is therefore relative to the
  INSTALLED layout, in which `luals/` sits inside the module tree — not to this
  file's position in the source repository, where `luals/` is a sibling of
  `src/`. The same installed path is already hard-coded in
  `src/clingy/cli/init.lua`'s `descriptor()`, which this file now supersedes as
  the single source of truth.
--]]

return {
  name = "clingy",

  -- The OnSetText plugin proper: injects `---@cast <param> clingy.Context<...>`
  -- after each `c.run(function(ctx)`.
  path = "luals/plugin.lua",

  -- Verified against luals-composer 0.1.0 (2026-09-10), 3-plugin composition
  -- against a real headless lua-language-server 3.18.2-dev.
  transport = "^0.1.0",
  contract = 1,

  -- Since clingy 0.6.1, `M.process_diffs` returns only ZERO-WIDTH hunks
  -- (`{ start = e + 1, finish = e, text = " ---@cast ..." }`) and `OnSetText`
  -- returns those or nil — it no longer returns a whole rewritten string.
  -- Insertions always compose, so this is the strict mode, and Composer
  -- enforces it per call rather than trusting the claim.
  text_edits = "insertions",

  args = {},
}
