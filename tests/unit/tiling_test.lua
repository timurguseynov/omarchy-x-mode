-- The tiling keymap: which keys the pack takes from Omarchy's tiler, what the panel
-- calls them, and what they used to do. Built per call with a fake `hl`, so the
-- table can be checked without a compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local tiling = dofile(repo .. "/hypr/x-mode/tiling.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
  end
end

local calls = {}
local hl = {
  dispatch = function(d) calls[#calls + 1] = { kind = "dispatch", payload = d } end,
  exec_cmd = function(cmd) calls[#calls + 1] = { kind = "exec", payload = cmd } end,
  dsp = {
    focus = function(opts) return { what = "focus", opts = opts } end,
    window = {
      resize = function(opts) return { what = "resize", opts = opts } end,
      swap = function(opts) return { what = "swap", opts = opts } end,
      float = function(opts) return { what = "float", opts = opts } end,
      pseudo = function() return { what = "pseudo" } end,
      move = function(opts) return { what = "move", opts = opts } end,
    },
    layout = function(a) return { what = "layout", args = a } end,
    workspace = { toggle_special = function(n) return { what = "special", name = n } end },
  },
}

local entries = tiling.keys(hl)

check("keys.not-empty", #entries > 0, true)

-- Every entry has to be usable by the binder: a key, a label for the panel, and
-- what Omarchy did with it -- a function to replay or a command string.
local complete = true
for _, e in ipairs(entries) do
  if type(e.keys) ~= "string" or e.keys == "" or type(e.label) ~= "string" or e.label == "" then
    complete = false
  end
  if type(e.omarchy) ~= "function" and type(e.omarchy) ~= "string" then
    complete = false
  end
end
check("keys.entries-complete", complete, true)

-- The two gaps spellings are the pack's own switch, and both are appended: Omarchy
-- writes the key by keycode, so a table with only the named one leaves the packet
-- key on the real desktop.
local gaps = {}
for _, e in ipairs(entries) do
  if e.label == "Toggle window gaps" then
    gaps[#gaps + 1] = e.keys
  end
end
check("gaps.count", #gaps, 2)
check("gaps.named", gaps[1], "SUPER + SHIFT + BACKSPACE")
check("gaps.by-code", gaps[2], "SUPER + SHIFT + code:22")

-- The gaps row replays an Omarchy command, not a chord the pack would send.
for _, e in ipairs(entries) do
  if e.label == "Toggle window gaps" then
    check("gaps.replay", e.omarchy, "omarchy-hyprland-window-gaps-toggle")
  end
end

-- A resize entry really asks for a relative resize with its own step.
local resize = nil
for _, e in ipairs(entries) do
  if e.keys == "SUPER + CTRL + code:20" then
    resize = e
  end
end
check("resize.present", resize ~= nil, true)
resize.omarchy()
check("resize.dispatches", calls[1].kind, "dispatch")
check("resize.relative", calls[1].payload.opts.relative, true)
check("resize.step-x", calls[1].payload.opts.x, -300)
check("resize.step-y", calls[1].payload.opts.y, 0)

-- Every key is listed once: a duplicate would bind the same chord twice.
local seen = {}
local duplicates = 0
for _, e in ipairs(entries) do
  if seen[e.keys] then
    duplicates = duplicates + 1
  end
  seen[e.keys] = true
end
check("keys.unique", duplicates, 0)

if failures > 0 then
  os.exit(1)
end
print("tiling ok")
