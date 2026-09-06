local composer_mod = require("clingy.presentation.composer")

local M = {}

M.Composer = composer_mod.ComposerHost
M.ComposerHost = composer_mod.ComposerHost
M.create_composer = composer_mod.create_composer
M.encode_json = composer_mod.encode_json

return M
