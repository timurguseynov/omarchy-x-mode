-- Config for the shared host (NEST_HOST=shared): one Hyprland of our own, on a
-- vkms card, as a session of its own, with the five test nests as its wayland
-- clients. Nothing of the pack is loaded here -- the host only has to serve
-- wayland (an output and a seat) and keep presenting. Everything the tests read
-- lives inside the nests, each of which renders to its own headless output.
--
-- Its devices are the one thing that has to be handled: the nests inherit the
-- host's seat, so libinput here reading this machine's real keyboard and mouse
-- would put whoever is at the keyboard into the tests. The harness writes the
-- rules (NEST_DEVICES_LUA) once the host is up, and the reload that follows
-- applies them to the devices already there.
hl.config({
  general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
  animations = { enabled = false },
  misc = { disable_hyprland_logo = true },
})

local devices = os.getenv("NEST_DEVICES_LUA")
if devices and devices ~= "" then
  pcall(dofile, devices)
end
