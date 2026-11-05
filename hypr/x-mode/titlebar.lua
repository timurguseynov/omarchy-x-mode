-- The titlebar the pack hands to the patched hyprbars: load the plugin before its
-- own keys are set, keep Omarchy's look on her own windows, and set the pack's bar
-- with the theme's colours and one close button.
--
-- This runs once, at config load, and it is the pack's contract with the plugin's C
-- side: every key set here is read there. That is why it is a module of its own and
-- why the unit test checks the keys rather than the calls.
local M = {}

-- opts: bar_bg, bar_fg (theme colours), bar_height (fallback when the plugin's own
-- key is not registered yet), so_path (the installed .so).
function M.install(hl, opts)
  opts = opts or {}

  -- The plugin has to be loaded before its own keys are set. Hyprland parses this
  -- file before anything has loaded it, and a `plugin:hyprbars:*` key that no
  -- plugin registered is reported as an unknown key and dropped -- a dozen errors
  -- on every login, with the bar height, the tab height and the colours lost on
  -- that parse. Only when there is a build to load: the nest has no installed copy
  -- (its harness loads the repo build itself).
  local so_path = opts.so_path
  if so_path ~= nil then
    local base = io.open(so_path, "r")
    if base ~= nil then
      base:close()
      if hl.plugin ~= nil and hl.plugin.load ~= nil then
        pcall(hl.plugin.load, so_path)
      end
    end
  end

  pcall(function()
    -- A reload re-runs Omarchy's titlebars() before this file. She writes her
    -- floating-workspace look into the plugin that is already loaded (this one) and
    -- appends her buttons. Keep that look for her windows, then put the pack's own
    -- back: the two never share a bar.
    local ok_tag, tag = pcall(hl.get_config, "plugin:hyprbars:workspace_tag")
    if ok_tag and type(tag) == "string" and tag ~= "" and hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.stash_omarchy then
      pcall(hl.plugin.hyprbars.stash_omarchy)
    end
    hl.config({
      plugin = {
        hyprbars = {
          enabled = true,
          bar_height = opts.bar_height,
          on_double_click = "",
          bar_color = opts.bar_bg,
          ["col.text"] = opts.bar_fg,
          bar_title_enabled = true,
          bar_text_size = 11,
          bar_text_font = "sans-serif",
          bar_text_align = "center",
          bar_buttons_alignment = "left",
          bar_part_of_window = true,
          bar_precedence_over_border = true,
          bar_padding = 10,
          bar_button_padding = 6,
          icon_on_hover = false,
          -- The ✕ shows and closes only on the current tab, and only while the
          -- group has focus; anywhere else clicking a tab focuses/switches instead.
          tab_close_active_only = true,
          -- Card width plus half of gaps_out. Set again after GAP_OUT is known.
          x_mode_dock_inset = 45,
        },
      },
    })
    if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then
      if hl.plugin.hyprbars.clear_buttons then
        hl.plugin.hyprbars.clear_buttons()
      end
      hl.plugin.hyprbars.add_button({
        -- Match the tabbar close (✕): the theme's text color, not macOS red.
        bg_color = opts.bar_fg,
        fg_color = opts.bar_fg,
        size = 12,
        icon = "",
        -- Close the whole group (all tabs) when grouped, otherwise just the
        -- window. The button action is run as a shell command, so it evals Lua via
        -- hyprctl.
        action = [[hyprctl eval 'local w=hl.get_active_window(); if w then if w.group then for _,m in ipairs(w.group.members) do hl.dispatch(hl.dsp.window.close({window=m})) end else hl.dispatch(hl.dsp.window.close({window=w})) end end']],
      })
    end
  end)
end

return M
