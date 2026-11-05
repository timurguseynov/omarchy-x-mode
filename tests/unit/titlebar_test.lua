-- The titlebar contract with the plugin's C side: which keys the pack sets, in
-- which shape, and that the plugin is loaded before them. A fake `hl` records the
-- calls, so this runs without a compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local titlebar = dofile(repo .. "/hypr/x-mode/titlebar.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

local function fake(tag, with_plugin)
  local f
  f = {
    loaded = {},
    configs = {},
    buttons = {},
    cleared = 0,
    plugin = {
      load = function(path) f.loaded[#f.loaded + 1] = path end,
    },
  }
  f.get_config = function() return tag end
  f.config = function(spec) f.configs[#f.configs + 1] = spec end
  if with_plugin then
    f.plugin.hyprbars = {
      stash_omarchy = function() f.stashed = (f.stashed or 0) + 1 end,
      clear_buttons = function() f.cleared = f.cleared + 1 end,
      add_button = function(b) f.buttons[#f.buttons + 1] = b end,
    }
  end
  return f
end

-- A build to load: the module checks the file exists before asking the plugin.
local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "/hyprbars'")
local so = dir .. "/hyprbars/x-mode-hyprbars.so"
local f = assert(io.open(so, "w"))
f:write("not a real plugin\n")
f:close()

local env = fake("omarchy-tag", true)
titlebar.install(env, { bar_bg = "#111111", bar_fg = "#eeeeee", bar_height = 24, so_path = so })

check("load.called", #env.loaded, 1)
check("load.path", env.loaded[1], so)
check("stash.called", env.stashed, 1)
check("config.once", #env.configs, 1)

local hb = env.configs[1] and env.configs[1].plugin and env.configs[1].plugin.hyprbars
check("config.enabled", hb and hb.enabled, true)
check("config.bar-height", hb and hb.bar_height, 24)
check("config.bar-color", hb and hb.bar_color, "#111111")
check("config.text-color", hb and hb["col.text"], "#eeeeee")
check("config.tab-close-active-only", hb and hb.tab_close_active_only, true)
check("config.dock-inset", hb and hb.x_mode_dock_inset, 45)
check("config.part-of-window", hb and hb.bar_part_of_window, true)

check("buttons.cleared", env.cleared, 1)
check("buttons.one", #env.buttons, 1)
check("buttons.colour", env.buttons[1] and env.buttons[1].bg_color, "#eeeeee")
check("buttons.action-closes-group", (env.buttons[1] and env.buttons[1].action or ""):find("group", 1, true) ~= nil, true)

-- No tag written by Omarchy: her look is not stashed, and the pack's bar is still
-- configured (that is the normal first load).
local env2 = fake("", true)
titlebar.install(env2, { bar_bg = "#111111", bar_fg = "#eeeeee", bar_height = 24 })
check("no-tag.no-stash", env2.stashed, nil)
check("no-tag.still-configured", #env2.configs, 1)

-- No build to load: the loader is not asked, and nothing else changes.
local env3 = fake("", true)
titlebar.install(env3, { bar_bg = "#111111", bar_fg = "#eeeeee", bar_height = 24, so_path = dir .. "/hyprbars/missing.so" })
check("no-so.not-loaded", #env3.loaded, 0)
check("no-so.still-configured", #env3.configs, 1)

-- No plugin at all (an older install): the config is still set, and no button work
-- is attempted.
local env4 = fake("", false)
titlebar.install(env4, { bar_bg = "#111111", bar_fg = "#eeeeee", bar_height = 24 })
check("no-plugin.configured", #env4.configs, 1)
check("no-plugin.no-buttons", #env4.buttons, 0)

os.execute("rm -rf '" .. dir .. "'")

if failures > 0 then
  os.exit(1)
end
print("titlebar ok")
