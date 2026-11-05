import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "logic.js" as Logic

// Shared app resolution for the dock and the panel: window class -> desktop
// entry -> icon, plus the bits the dock's context menu needs from the same
// entry (display name, the "New Window" action, single-instance).
//
// Kept as a plain component (not a singleton) so both Dock.qml and Panel.qml
// can instantiate it without a qmldir. The dock owns the one its switcher
// reuses (Switcher.dock); the panel keeps its own: it loads from the
// bar-widget entry point, which may live in another shell process where a
// singleton would not share the scan anyway.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  // window class / app id -> icon name from the desktop entry's Icon=.
  property var desktopIconMap: ({})
  // window class / app id -> { id, name, cmd } for the same entries. `cmd` is
  // the "New Window" action's command when the entry declares one, else null.
  property var desktopAppMap: ({})
  // [ { host, icon, id, name, cmd } ] for Chromium web apps, longest host first.
  property var desktopHostIcons: []
  // Desktop-entry ids (and their StartupWMClass) that declare a single main
  // window, so launching one only focuses the running instance.
  property var singleInstanceApps: ({})
  property var pendingSingleInstance: ({})
  // chromium extension id (32 chars a..p) -> icon file path.
  property var extensionIcons: ({})
  property var pendingExtensionIcons: ({})

  // Scan commands are pure string building in logic.js (unit tested there);
  // this component only runs them.
  function iconScanCommand() {
    return Logic.iconScanCommand()
  }

  // One id/StartupWMClass per desktop entry that declares it opens a single
  // main window: launching such an app activates the existing instance instead
  // of creating a new window, so there is no tab to open.
  function singleInstanceScanCommand() {
    return Logic.singleInstanceScanCommand()
  }

  // Resolve an icon *name* (desktop entry Icon= value) to a loadable URL, going
  // through the on-disk index first: Qt's themed lookup misses icons installed
  // after the shell started (its theme cache never rescans).
  function resolveIconName(name) {
    var n = String(name || "").trim()
    if (n === "")
      return ""
    if (n.charAt(0) === "/")
      return Util.fileUrl(n)
    var p = root.iconIndex[n]
    if (p)
      return Util.fileUrl(p)
    var themed = Quickshell.iconPath(n, true)
    if (themed && themed.length > 0)
      return themed
    return ""
  }

  function hostIconFor(cls) {
    const h = Logic.hostMatch(cls, root.desktopHostIcons)
    return h === null ? "" : root.resolveIconName(h.icon)
  }

  // Find the largest icon declared in every Chromium extension manifest under
  // the browser profiles and key it by the 32-char extension id ("a".."p").
  function extensionScanCommand() {
    return Logic.extensionScanCommand()
  }

  function extensionIconFor(cls) {
    const id = Logic.extensionIdFor(cls)
    if (id === "")
      return ""
    const p = root.extensionIcons[id]
    return p ? Util.fileUrl(p) : ""
  }

  // Command of the desktop entry's "New Window" action, when it has one (e.g.
  // Sublime Text's `subl --launch-or-new-window`). Launching the bare entry
  // would just focus the running instance for such apps.
  function newWindowActionCommand(e) {
    var acts = (e && e.actions) || []
    for (var j = 0; j < acts.length; j++) {
      var a = acts[j]
      if (!a)
        continue
      var id = String(a.id || "").toLowerCase().replace(/[\s_]+/g, "-")
      var name = String(a.name || "").toLowerCase()
      if (id.indexOf("new") === -1)
        continue
      if (id.indexOf("window") === -1 && name.indexOf("window") === -1)
        continue
      if (id.indexOf("private") !== -1 || id.indexOf("incognito") !== -1)
        continue
      if (name.indexOf("private") !== -1 || name.indexOf("incognito") !== -1)
        continue
      return a.command
    }
    return null
  }

  // The fold itself is Logic.buildDesktopIcons, unit tested without a compositor.
  // What stays here is the Qt part: reading the entries and asking for the command.
  function rebuildDesktopIcons() {
    var values = []
    try {
      values = DesktopEntries.applications.values || []
    } catch (e) {
      values = []
    }
    var entries = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      entries.push({
        id: String((e && e.id) || ""),
        startupClass: String((e && e.startupClass) || ""),
        icon: String((e && e.icon) || ""),
        name: String((e && e.name) || ""),
        execString: String((e && e.execString) || ""),
        cmd: root.newWindowActionCommand(e),
      })
    }
    var built = Logic.buildDesktopIcons(entries)
    root.desktopIconMap = built.icons
    root.desktopAppMap = built.apps
    root.desktopHostIcons = built.hosts
  }

  // Desktop entry matching a window class: the key map first, then the URL host
  // for Chromium web apps (whose class embeds it). Returns { id, name, cmd }.
  function appEntryFor(cls) {
    const e = Logic.lookupByClass(root.desktopAppMap, cls)
    if (e !== undefined)
      return e
    return Logic.hostMatch(cls, root.desktopHostIcons)
  }

  // Human-readable app name, from the desktop entry keys used for icons; falls
  // back to the last dotted class segment.
  function appDisplayName(cls) {
    const e = root.appEntryFor(cls)
    return Logic.displayNameFor(cls, e && e.name ? e.name : "")
  }

  // True when the app's desktop entry declares it single-instance, so a launch
  // would only focus the running window (nothing new to open as a tab).
  function isSingleInstance(cls) {
    // Truthiness, not `=== true`: the scan writes what it finds, and the old
    // lookup treated any value as "single instance".
    return !!Logic.lookupByClass(root.singleInstanceApps, cls)
  }

  function desktopIconFor(cls) {
    // An empty class has no icon at all, and must not fall through to the host and
    // extension lookups the way a class with no desktop entry does.
    if (Logic.classKey(cls) === "")
      return ""
    const name = Logic.lookupByClass(root.desktopIconMap, cls)
    if (name !== undefined)
      return root.resolveIconName(name)
    // Both lookups are given the class as it was written; each normalises it
    // itself (classKey inside hostMatch and extensionIdFor), which is what makes a
    // "chrome-<id>.desktop" class still find its extension icon.
    const h = root.hostIconFor(cls)
    if (h !== "")
      return h
    return root.extensionIconFor(cls)
  }

  function iconFor(cls) {
    var raw = String(cls || "")
    var cleaned = Logic.cleanName(raw)
    // Direct candidates first (a class that already is the icon name), then the
    // desktop entry's Icon= value, then the loose last segment.
    var candidates = [raw, cleaned, Logic.lastSegment(cleaned)]
    for (var i = 0; i < candidates.length; i++) {
      var p = root.resolveIconName(candidates[i])
      if (p !== "")
        return p
    }
    var de = root.desktopIconFor(raw)
    if (de !== "")
      return de
    // Nothing matched: "" rather than a generic icon. AppIcon draws the class
    // initial for an iconless class ("A" for the nest's aquamarine, "Z" for
    // dev.zed.Zed), and that says which window it is where
    // `application-x-executable` -- a gear in Yaru, Adwaita and Breeze -- says
    // nothing and only hides the letter.
    return ""
  }

  Process {
    id: iconScan
    command: ["bash", "-c", root.iconScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line || "").trim()
        if (path === "")
          return
        var base = path.substring(path.lastIndexOf("/") + 1)
        var dot = base.lastIndexOf(".")
        var name = dot > 0 ? base.substring(0, dot) : base
        if (root.pendingIconIndex[name] === undefined)
          root.pendingIconIndex[name] = path
      }
    }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Process {
    id: singleInstanceScan
    command: ["bash", "-c", root.singleInstanceScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line || "").split("\t")
        var id = String(t[0] || "").toLowerCase().trim()
        if (id.slice(-8) === ".desktop")
          id = id.slice(0, -8)
        var wm = String(t.length > 1 ? t[1] : "").toLowerCase().trim()
        if (wm.slice(-8) === ".desktop")
          wm = wm.slice(0, -8)
        if (id !== "")
          root.pendingSingleInstance[id] = true
        if (wm !== "")
          root.pendingSingleInstance[wm] = true
      }
    }
    onStarted: root.pendingSingleInstance = ({})
    onExited: root.singleInstanceApps = root.pendingSingleInstance
  }

  Process {
    id: extensionScan
    command: ["bash", "-c", root.extensionScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line || "").split("\t")
        if (t.length < 2)
          return
        var id = t[0].trim()
        var path = t.slice(1).join("\t").trim()
        if (id !== "" && path !== "" && root.pendingExtensionIcons[id] === undefined)
          root.pendingExtensionIcons[id] = path
      }
    }
    onStarted: root.pendingExtensionIcons = ({})
    onExited: root.extensionIcons = root.pendingExtensionIcons
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.rebuildDesktopIcons()
      // A new app installs an icon next to its .desktop entry; rescan the
      // on-disk icon index so it appears without a shell restart. Debounced
      // because a package install touches many entries at once.
      iconRescan.restart()
      if (!singleInstanceScan.running)
        singleInstanceScan.running = true
    }
  }

  Timer {
    id: iconRescan
    interval: 750
    repeat: false
    onTriggered: if (!iconScan.running) iconScan.running = true
  }

  // Catch icon-only changes (an app updating its icon) and newly installed
  // browser extensions, which do not touch a .desktop entry.
  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: {
      if (!iconScan.running)
        iconScan.running = true
      if (!extensionScan.running)
        extensionScan.running = true
      if (!singleInstanceScan.running)
        singleInstanceScan.running = true
    }
  }

  Component.onCompleted: {
    iconScan.running = true
    extensionScan.running = true
    singleInstanceScan.running = true
    root.rebuildDesktopIcons()
  }
}