local host_mod = require("clingy.presentation.host")
local composer_mod = require("clingy.presentation.composer")
local prompt_mod = require("clingy.presentation.prompt")
local null_host_mod = require("clingy.presentation.null_host")
local recording_host_mod = require("clingy.presentation.recording_host")
local failing_host_mod = require("clingy.presentation.failing_host")

local M = {}

M.PresentationHost = host_mod.PresentationHost
M.is_host = host_mod.is_host

M.Composer = composer_mod.ComposerHost
M.ComposerHost = composer_mod.ComposerHost
M.create_composer = composer_mod.create_composer
M.composer = composer_mod.create_composer

M.NullHost = null_host_mod.NullHost
M.create_null_host = null_host_mod.create
M.null_host = null_host_mod.create

M.RecordingHost = recording_host_mod.RecordingHost
M.create_recording_host = recording_host_mod.create
M.recording_host = recording_host_mod.create

M.FailingHost = failing_host_mod.FailingHost
M.create_failing_host = failing_host_mod.create
M.failing_host = failing_host_mod.create

M.prompt = prompt_mod

return M
