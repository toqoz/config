local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

config.automatically_reload_config = true
config.check_for_updates = false

-- Marker consumed by .zshrc to auto-launch tmux only for shells spawned
-- directly by wezterm. The rc unsets it so children don't re-trigger.
config.set_environment_variables = {
	WEZTERM_AUTORUN = "1",
}

config.font = wezterm.font_with_fallback({
	"JetBrains Mono",
	"Noto Color Emoji",
	"Symbols Nerd Font Mono",
})

config.line_height = 1.2
config.window_background_opacity = 0.85
config.macos_window_background_blur = 20

config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.window_close_confirmation = "NeverPrompt"
-- config.use_fancy_tab_bar = false

config.show_new_tab_button_in_tab_bar = false
config.show_close_tab_button_in_tabs = false

config.enable_kitty_keyboard = true
config.use_ime = true
-- for macSKK's C-j: SHIFT (default) -> SHIFT|CTRL
config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"

config.color_scheme = "Catppuccin Mocha"

-- ----------------------------------------------------------
-- Keys
-- ----------------------------------------------------------
config.keys = {
	-- Disable C-j for macSKK
	{
		key = "j",
		mods = "CTRL",
		action = wezterm.action.DisableDefaultAssignment,
	},

	-- Disable CMD+Q to prevent accidental quit.
	{
		key = "q",
		mods = "CMD",
		action = wezterm.action.DisableDefaultAssignment,
	},

	-- Send Alt-Enter through to pi; WezTerm otherwise treats it as a window shortcut.
	{
		key = "Enter",
		mods = "SHIFT",
		action = act.SendKey({ key = "m", mods = "ALT" }),
	},

	-- Command palette
	{
		key = "p",
		mods = "CMD|SHIFT",
		action = act.ActivateCommandPalette,
	},
}

return config
