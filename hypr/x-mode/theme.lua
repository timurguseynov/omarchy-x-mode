-- Theme colors for the titlebar/tabbar: parse the palette the shell also writes
-- (~/.local/state/omarchy/current/theme/colors.toml) and turn it into the rgb()
-- strings hyprbars wants. Pure: the input is the file's text, so it can be
-- tested with plain lua (tests/unit/theme_test.lua).
local M = {}

-- A small TOML subset: `key = value` lines, an optional inline comment and
-- optional quotes. A '#' only starts a comment after whitespace, so a '#rrggbb'
-- value survives.
function M.parse_toml(raw)
  local colors = {}
  for line in tostring(raw or ""):gmatch("[^\n]*") do
    local key, value = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if key ~= nil and value ~= nil and value ~= "" then
      value = value:gsub("%s+#.*$", "")
      value = value:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
      colors[key] = value
    end
  end
  return colors
end

-- "#rrggbb" / "#rgb" / "rgb(...)" -> "rgb(r,g,b)", or nil when it cannot be
-- parsed.
function M.to_hypr_color(value)
  local v = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then
    return nil
  end
  if v:match("^rgba?%(") then
    return v
  end
  local h = v:gsub("#", "")
  if #h == 3 then
    h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2)
  end
  if #h < 6 then
    return nil
  end
  local r = tonumber(h:sub(1, 2), 16)
  local g = tonumber(h:sub(3, 4), 16)
  local b = tonumber(h:sub(5, 6), 16)
  if r == nil or g == nil or b == nil then
    return nil
  end
  return string.format("rgb(%d,%d,%d)", r, g, b)
end

-- The bar background/foreground for hyprbars, with the defaults the desktop has
-- always used when the palette is missing or unparseable.
function M.bar_colors(palette)
  palette = palette or {}
  local bg = M.to_hypr_color(palette.background or palette.bg or palette.color0) or "rgb(55, 55, 58)"
  local fg = M.to_hypr_color(palette.foreground or palette.fg or palette.color7) or "rgb(255, 255, 255)"
  return bg, fg
end

return M
