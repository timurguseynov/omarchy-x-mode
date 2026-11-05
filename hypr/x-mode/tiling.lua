-- The tiling keys the pack rebinds, as data: what the key is, what the panel shows,
-- and what Omarchy did with it. The pack's own handler for each is in x-mode.lua --
-- this table only says which keys are taken and what they used to do, so the file
-- that wires events does not also carry sixty lines of keymap.
--
-- The entries hold closures, so they are built per call: a module-level table would
-- be shared with whoever asked for it.
local M = {}

-- A resize step, in the direction Hyprland takes for a relative resize.
function M.resize_step(hl, x, y)
  return function()
    hl.dispatch(hl.dsp.window.resize({ x = x, y = y, relative = true }))
  end
end

function M.keys(hl)
  local resize_step = function(x, y)
    return M.resize_step(hl, x, y)
  end

  local entries = {
    -- Focus, the four arrows.
    { keys = "SUPER + LEFT", label = "Focus on left window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end },
    { keys = "SUPER + RIGHT", label = "Focus on right window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end },
    { keys = "SUPER + UP", label = "Focus on above window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "u" })) end },
    { keys = "SUPER + DOWN", label = "Focus on below window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "d" })) end },
    -- Swap with the neighbour (Omarchy's Shift+arrows).
    { keys = "SUPER + SHIFT + LEFT", label = "Swap window to the left", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "l" })) end },
    { keys = "SUPER + SHIFT + RIGHT", label = "Swap window to the right", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "r" })) end },
    { keys = "SUPER + SHIFT + UP", label = "Swap window up", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "u" })) end },
    { keys = "SUPER + SHIFT + DOWN", label = "Swap window down", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "d" })) end },
    -- The resize steps: Cmd +/- and its Shift, Alt and Ctrl variants.
    { keys = "SUPER + code:20", label = "Expand window left", omarchy = resize_step(-100, 0) },
    { keys = "SUPER + code:21", label = "Shrink window left", omarchy = resize_step(100, 0) },
    { keys = "SUPER + SHIFT + code:20", label = "Shrink window up", omarchy = resize_step(0, -100) },
    { keys = "SUPER + SHIFT + code:21", label = "Expand window down", omarchy = resize_step(0, 100) },
    { keys = "SUPER + ALT + code:20", label = "Expand window left a little", omarchy = resize_step(-25, 0) },
    { keys = "SUPER + ALT + code:21", label = "Shrink window left a little", omarchy = resize_step(25, 0) },
    { keys = "SUPER + SHIFT + ALT + code:20", label = "Shrink window up a little", omarchy = resize_step(0, -25) },
    { keys = "SUPER + SHIFT + ALT + code:21", label = "Expand window down a little", omarchy = resize_step(0, 25) },
    { keys = "SUPER + CTRL + code:20", label = "Expand window left a lot", omarchy = resize_step(-300, 0) },
    { keys = "SUPER + CTRL + code:21", label = "Shrink window left a lot", omarchy = resize_step(300, 0) },
    { keys = "SUPER + CTRL + SHIFT + code:20", label = "Shrink window up a lot", omarchy = resize_step(0, -300) },
    { keys = "SUPER + CTRL + SHIFT + code:21", label = "Expand window down a lot", omarchy = resize_step(0, 300) },
    -- The layout toggles.
    { keys = "SUPER + T", label = "Toggle window floating/tiling", omarchy = function() hl.dispatch(hl.dsp.window.float({ action = "toggle" })) end },
    { keys = "SUPER + J", label = "Toggle window split", omarchy = function() hl.dispatch(hl.dsp.layout("togglesplit")) end },
    { keys = "SUPER + P", label = "Pseudo window", omarchy = function() hl.dispatch(hl.dsp.window.pseudo()) end },
    { keys = "SUPER + O", label = "Pop window out (float & pin)", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-pop") end },
    { keys = "SUPER + CTRL + F", label = "Tiled full screen", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-tiled-fullscreen-toggle") end },
    { keys = "SUPER + Home", label = "Restore window width", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-width restore") end },
    { keys = "SUPER + ALT + Home", label = "Save window width", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-width save") end },
    -- The scratchpad pair.
    { keys = "SUPER + S", label = "Toggle scratchpad", omarchy = function() hl.dispatch(hl.dsp.workspace.toggle_special("scratchpad")) end },
    { keys = "SUPER + ALT + S", label = "Move window to scratchpad", omarchy = function() hl.dispatch(hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })) end },
  }

  -- The gaps toggle is the pack's own switch (the panel's "No gaps"), so in xmode
  -- the key is taken and does nothing; every other mode keeps Omarchy's key. Both
  -- spellings, since Omarchy writes it by keycode.
  for _, keys in ipairs({ "SUPER + SHIFT + BACKSPACE", "SUPER + SHIFT + code:22" }) do
    table.insert(entries, { keys = keys, label = "Toggle window gaps", omarchy = "omarchy-hyprland-window-gaps-toggle" })
  end

  return entries
end

return M
