-- theme.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local theme = dofile(repo .. "/hypr/x-mode/theme.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- hex, short hex, rgb() passthrough, whitespace, junk
check("hex", theme.to_hypr_color("#1e1e2e"), "rgb(30,30,46)")
check("short-hex", theme.to_hypr_color("#fff"), "rgb(255,255,255)")
check("rgb-passthrough", theme.to_hypr_color("rgba(1, 2, 3, 0.5)"), "rgba(1, 2, 3, 0.5)")
check("spaces", theme.to_hypr_color("  #000000  "), "rgb(0,0,0)")
check("junk", theme.to_hypr_color("nope"), nil)
check("empty", theme.to_hypr_color(""), nil)
check("nil", theme.to_hypr_color(nil), nil)

-- The TOML subset: an inline comment after whitespace is stripped, quotes come
-- off, and a '#' inside a value survives.
local raw = [[
# a comment line
background = "#1e1e2e" # dark
foreground = '#cdd6f4'
color0 = "#000000"
not=a=value
]]
local p = theme.parse_toml(raw)
check("toml.background", p.background, "#1e1e2e")
check("toml.foreground", p.foreground, "#cdd6f4")
check("toml.color0", p.color0, "#000000")
check("toml.ignores-comment-line", p["# a comment line"], nil)

-- The bar colors, with the named fallbacks and the built-in defaults.
local bg, fg = theme.bar_colors({ background = "#101010", foreground = "#eeeeee" })
check("bar.background", bg, "rgb(16,16,16)")
check("bar.foreground", fg, "rgb(238,238,238)")

local cbg, cfg = theme.bar_colors({ color0 = "#000000", color7 = "#ffffff" })
check("bar.color0", cbg, "rgb(0,0,0)")
check("bar.color7", cfg, "rgb(255,255,255)")

local dbg, dfg = theme.bar_colors({})
check("bar.default.background", dbg, "rgb(55, 55, 58)")
check("bar.default.foreground", dfg, "rgb(255, 255, 255)")

if failures > 0 then
  os.exit(1)
end
print("theme ok")
