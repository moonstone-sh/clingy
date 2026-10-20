local variants_ok, variants = pcall(function() return require("moonstone.variants") end)
if variants_ok then variants.install() end

return require("clingy.init")
