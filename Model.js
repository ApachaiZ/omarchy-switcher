// Pure helpers for the Switcher service.
//
// The service reads Hyprland's client list only when the overlay opens and
// keeps no window history. All strings that reach QML Text are rendered with
// Text.PlainText; this module only normalises and filters the data.

function validAddress(value) {
  var text = String(value || "").trim()
  return /^0x[0-9a-fA-F]+$/.test(text) ? text : ""
}

function validAppId(value) {
  var text = String(value || "").trim()
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(text) ? text : ""
}

// Dropdown persists appId -> { address, class, hidden, ... } in its state
// file. Only the address and app id are needed here; both are validated so a
// corrupt or edited file cannot inject a selector or a command argument.
function parseDropdownState(raw) {
  var out = ({})
  try {
    var parsed = JSON.parse(String(raw || ""))
    var apps = parsed && parsed.apps
    if (!apps || typeof apps !== "object") return out
    for (var key in apps) {
      var entry = apps[key]
      if (!entry || typeof entry !== "object") continue
      var address = validAddress(entry.address)
      var appId = validAppId(key)
      if (!address || !appId) continue
      out[address.toLowerCase()] = {
        appId: appId,
        cls: String(entry.class || ""),
        hidden: entry.hidden === true
      }
    }
  } catch (e) {
  }
  return out
}

// Icon names that reach Quickshell.iconPath are restricted to a desktop-entry
// style name: no slash, colon, URL, traversal or whitespace. This keeps an
// app-controlled class or title from becoming an image path.
function safeIconName(value) {
  var text = String(value || "").trim()
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(text) ? text : ""
}

// Only local image sources can reach Image.source. File paths and the
// in-process image provider are accepted; remote schemes are rejected.
function safeIconSource(value) {
  var text = String(value || "").trim()
  if (!text) return ""
  if (text.indexOf("file://") === 0 || text.indexOf("image://") === 0) return text
  if (text.charAt(0) === "/") return text
  return ""
}

// Whether Dropdown is enabled according to shell.json. It is a bar widget, so
// its id appears in bar.layout.* while enabled; disabledPlugins is checked too.
function dropdownEnabledFromShellConfig(raw) {
  try {
    var config = JSON.parse(String(raw || "{}"))
    if (!config || typeof config !== "object") return false
    var disabled = Array.isArray(config.disabledPlugins) ? config.disabledPlugins : []
    if (disabled.indexOf("apach.dropdown") !== -1) return false
    // Dropdown is a bar widget, so its id normally appears in bar.layout.*.
    // It can also be enabled as a service/overlay without a bar placement;
    // those live in the plugins array.
    var layout = config.bar && config.bar.layout
    var sections = ["left", "center", "right"]
    if (layout && typeof layout === "object") {
      for (var s = 0; s < sections.length; s++) {
        var list = layout[sections[s]]
        if (!Array.isArray(list)) continue
        for (var i = 0; i < list.length; i++) {
          var entry = list[i]
          var id = entry && typeof entry === "object" ? String(entry.id || "") : String(entry || "")
          if (id === "apach.dropdown") return true
        }
      }
    }
    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (var p = 0; p < plugins.length; p++) {
      var plugin = plugins[p]
      if (plugin && String(plugin.id || "") === "apach.dropdown") return true
    }
  } catch (e) {
  }
  return false
}

// Build the flat card list. One card per window, most recently focused first.
// mode "dropdown" keeps only windows whose address is present in the Dropdown
// state map; mode "all" keeps every mapped window.
function parseClients(raw, dropdownWindows, mode) {
  var list = []
  try {
    var clients = JSON.parse(String(raw || ""))
    if (!Array.isArray(clients)) return list
    for (var i = 0; i < clients.length; i++) {
      var client = clients[i]
      if (!client || client.mapped === false) continue
      var address = validAddress(client.address)
      if (!address) continue
      var cls = String(client.class || "")
      if (cls === "apach.switcher") continue
      var title = String(client.title || "") || cls || "Window"
      var dropdown = dropdownWindows[address.toLowerCase()] || null
      // The two modes are disjoint: all windows means windows that Dropdown
      // does not manage, and dropdown means only Dropdown windows.
      if (mode === "all" && dropdown) continue
      if (mode === "dropdown" && !dropdown) continue
      var workspace = client.workspace && typeof client.workspace === "object"
        ? String(client.workspace.name || "") : ""
      var tags = Array.isArray(client.tags) ? client.tags : []
      var hidden = tags.indexOf("dropdown-hidden") !== -1 ||
        workspace.indexOf("special:") === 0
      var focus = Number(client.focusHistoryID)
      if (!isFinite(focus)) focus = 9999
      list.push({
        addr: address,
        cls: cls,
        title: title,
        appId: dropdown ? dropdown.appId : "",
        dropdown: !!dropdown,
        hidden: hidden,
        focus: focus,
        workspace: workspace
      })
    }
  } catch (e) {
  }
  list.sort(function(a, b) {
    if (a.focus !== b.focus) return a.focus - b.focus
    return a.title.localeCompare(b.title)
  })
  return list
}

// Classic Alt-Tab starts on the previous window, not the current one; a
// reverse summon starts on the oldest entry.
function initialIndex(length, reverse) {
  if (!length) return -1
  if (reverse) return length - 1
  return length > 1 ? 1 : 0
}

function shortcutPresets() {
  return [
    { id: "ctrl-tab", label: "Ctrl + Tab", key: "CTRL + TAB", reverse: "CTRL + SHIFT + TAB" },
    { id: "super-tab", label: "Super + Tab", key: "SUPER + TAB", reverse: "SUPER + SHIFT + TAB" },
    { id: "ctrl-space", label: "Ctrl + Space", key: "CTRL + SPACE", reverse: "CTRL + SHIFT + SPACE" }
  ]
}

// Only chords that Omarchy leaves free by default. Super+Tab is deliberately
// absent: Omarchy uses it for "next workspace".
function allShortcutPresets() {
  return [
    { id: "alt-tab", label: "Alt + Tab", key: "ALT + TAB", reverse: "ALT + SHIFT + TAB" },
    { id: "alt-grave", label: "Alt + `", key: "ALT + GRAVE", reverse: "ALT + SHIFT + GRAVE" }
  ]
}

function allPresetForKey(key) {
  var wanted = String(key || "").trim().toUpperCase()
  var presets = allShortcutPresets()
  for (var i = 0; i < presets.length; i++)
    if (presets[i].key === wanted) return presets[i]
  return presets[0]
}

function safeScreenName(value) {
  var text = String(value || "").trim()
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(text) ? text : ""
}

// Screens the overlay is rendered on. The focused monitor is always included:
// a configuration that mirrors selected secondary screens must never make the
// overlay invisible from the screen the user is looking at.
function displayScreensFor(settings, screenNames, activeName) {
  var value = settings || defaultSettings()
  var available = Array.isArray(screenNames) ? screenNames : []
  var active = String(activeName || "")
  var out = []

  if (value.followActive) {
    if (active) out.push(active)
    return out
  }

  var wanted = Array.isArray(value.screens) ? value.screens : []
  for (var i = 0; i < available.length; i++) {
    var name = String(available[i] || "")
    if (name && wanted.indexOf(name) !== -1 && out.indexOf(name) === -1) out.push(name)
  }
  if (active && out.indexOf(active) === -1) out.push(active)
  return out
}

function nonCollidingPreset(key) {
  var presets = shortcutPresets()
  for (var i = 0; i < presets.length; i++)
    if (presets[i].key !== key) return presets[i]
  return presets[0]
}

// The all-windows and Dropdown shortcuts must never be the same chord: one
// would silently mask the other.
function normalizedShortcuts(value) {
  var source = value || {}
  var allShortcut = allPresetForKey(source.allShortcut).key
  var dropdownShortcut = presetForKey(source.dropdownShortcut).key
  if (dropdownShortcut === allShortcut) dropdownShortcut = nonCollidingPreset(allShortcut).key
  return { allShortcut: allShortcut, dropdownShortcut: dropdownShortcut }
}

function defaultSettings() {
  return {
    version: 1,
    allShortcut: "ALT + TAB",
    dropdownShortcut: "CTRL + TAB",
    followActive: true,
    screens: []
  }
}

function presetForKey(key) {
  var wanted = String(key || "").trim().toUpperCase()
  var presets = shortcutPresets()
  for (var i = 0; i < presets.length; i++)
    if (presets[i].key === wanted) return presets[i]
  return presets[0]
}

function parseSettings(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object") return defaultSettings()
    var screens = []
    if (Array.isArray(parsed.screens)) {
      for (var i = 0; i < parsed.screens.length; i++) {
        var name = safeScreenName(parsed.screens[i])
        if (name && screens.indexOf(name) === -1) screens.push(name)
      }
    }
    var shortcuts = normalizedShortcuts(parsed)
    return {
      version: 1,
      allShortcut: shortcuts.allShortcut,
      dropdownShortcut: shortcuts.dropdownShortcut,
      followActive: parsed.followActive !== false,
      screens: screens
    }
  } catch (e) {
  }
  return defaultSettings()
}

function serializeSettings(settings) {
  var value = settings || defaultSettings()
  var screens = []
  if (Array.isArray(value.screens)) {
    for (var i = 0; i < value.screens.length; i++) {
      var name = safeScreenName(value.screens[i])
      if (name && screens.indexOf(name) === -1) screens.push(name)
    }
  }
  var shortcuts = normalizedShortcuts(value)
  return JSON.stringify({
    version: 1,
    allShortcut: shortcuts.allShortcut,
    dropdownShortcut: shortcuts.dropdownShortcut,
    followActive: value.followActive !== false,
    screens: screens
  }, null, 2) + "\n"
}

function layerRuleLine() {
  return 'hl.layer_rule({ match = { namespace = "apach-switcher" }, blur = true, ignore_alpha = 0.15, no_anim = true })'
}

// Generated Hyprland Lua for the optional static install. The inline file is
// intentionally small and contains no user data. The bind table comes from the
// same entries as the runtime eval, so both modes cannot drift apart.
function luaForSettings(settings) {
  var chords = boundChords(settings)
  var binds = bindEntries(settings, true)
  var lines = [
    "-- Generated by apach.switcher. Edit the shortcut in Switcher settings.",
    layerRuleLine(),
    ""
  ]

  for (var i = 0; i < chords.length; i++)
    lines.push("hl.unbind(" + luaString(chords[i]) + ")")
  lines.push("")

  for (var j = 0; j < binds.length; j++)
    if (!binds[j].dropdown) lines.push(oBindLine(binds[j]))

  // Dropdown is a separate plugin: Hyprland reads shell.json once at load time
  // instead of watching it like the running service does.
  lines.push(
    "local function switcherHasDropdown()",
    '  local file = io.open(os.getenv("HOME") .. "/.config/omarchy/shell.json", "r")',
    "  if not file then return false end",
    '  local data = file:read("*a") or ""',
    "  file:close()",
    '  return data:find(\'"apach.dropdown"\', 1, true) ~= nil',
    "end",
    "if switcherHasDropdown() then"
  )
  for (var k = 0; k < binds.length; k++)
    if (binds[k].dropdown) lines.push("  " + oBindLine(binds[k]))
  lines.push("end", "")

  return lines.join("\n")
}

function oBindLine(bind) {
  return "o.bind(" + luaString(bind.chord) + ", " +
    luaString(bind.description) + ", " + luaString(bind.command) + ")"
}

// ---- Hyprland keyboard integration ----
//
// The service owns its shortcuts when no legacy static file exists: it sends
// one expression to `hyprctl eval`, so a plain `omarchy plugin add` writes
// nothing outside the plugin folder. Hyprland drops runtime binds and layer
// rules on every config reload, so the service re-evaluates that expression
// when it sees the `configreloaded` event. A `~/.config/hypr/switcher.lua`
// written by an older installer takes precedence and keeps the static path.
//
// Binds are expressed as data so the two generators cannot drift apart.

function bindEntries(settings, dropdownEnabled) {
  var source = settings || defaultSettings()
  var all = allPresetForKey(source.allShortcut)
  var preset = presetForKey(source.dropdownShortcut)
  var list = [
    {
      chord: all.key,
      description: "Switcher: all windows",
      command: "omarchy-shell -q apach.switcher next",
      dropdown: false
    },
    {
      chord: all.reverse,
      description: "Switcher: reverse windows",
      command: "omarchy-shell -q apach.switcher prev",
      dropdown: false
    }
  ]
  if (dropdownEnabled) {
    list.push({
      chord: preset.key,
      description: "Switcher: Dropdown windows",
      command: "omarchy-shell -q apach.switcher nextDropdown",
      dropdown: true
    })
    list.push({
      chord: preset.reverse,
      description: "Switcher: reverse Dropdown windows",
      command: "omarchy-shell -q apach.switcher prevDropdown",
      dropdown: true
    })
  }
  return list
}

function pushUnique(list, value) {
  if (list.indexOf(value) === -1) list.push(value)
}

// Every chord the plugin may own right now, plus the previously applied
// presets when a shortcut just changed. All of them are unbound before a bind:
// runtime registration has no config reload behind it, so a stale preset would
// otherwise keep its key.
function boundChords(settings, previous) {
  var source = settings || defaultSettings()
  var all = allPresetForKey(source.allShortcut)
  var dropdown = presetForKey(source.dropdownShortcut)
  var chords = []
  pushUnique(chords, all.key)
  pushUnique(chords, all.reverse)
  pushUnique(chords, dropdown.key)
  pushUnique(chords, dropdown.reverse)
  if (previous) {
    var previousAll = allPresetForKey(previous.allShortcut)
    var previousDropdown = presetForKey(previous.dropdownShortcut)
    pushUnique(chords, previousAll.key)
    pushUnique(chords, previousAll.reverse)
    pushUnique(chords, previousDropdown.key)
    pushUnique(chords, previousDropdown.reverse)
  }
  return chords
}

// Chords that should end up bound, which is what a post-reload verification
// checks. Unlike boundChords, this omits the Dropdown pair when Dropdown is
// disabled.
function activeChords(settings, dropdownEnabled) {
  var binds = bindEntries(settings, dropdownEnabled)
  var chords = []
  for (var i = 0; i < binds.length; i++) pushUnique(chords, binds[i].chord)
  return chords
}

var BIND_MODIFIERS = { ALT: 8, SHIFT: 1, CTRL: 4, SUPER: 64 }

// Binds Omarchy ships on the chords the switcher takes over. Seeing them is
// expected; anything else on those chords is reported as a conflict.
var BENIGN_BINDS = [
  "Focus on next window",
  "Focus on previous window",
  "Reveal active window on top"
]

function chordToBind(chord) {
  var parts = String(chord || "").split("+")
  var modmask = 0
  var key = ""
  for (var i = 0; i < parts.length; i++) {
    var token = parts[i].trim().toUpperCase()
    if (!token) continue
    if (BIND_MODIFIERS[token] !== undefined) modmask = modmask | BIND_MODIFIERS[token]
    else key = token
  }
  return { modmask: modmask, key: key }
}

// Compare the live Hyprland bind table with the chords the service should own.
// `hyprctl binds -j` reports modmask and key, not the chord string, so chords
// are converted first. Descriptions only; no window or application data.
function parseBinds(raw, chords) {
  var binds = []
  try {
    binds = JSON.parse(String(raw || "[]"))
  } catch (e) {
    binds = []
  }
  if (!Array.isArray(binds)) binds = []

  var owners = {}
  var missing = []
  var conflicts = []
  for (var i = 0; i < chords.length; i++) {
    var chord = String(chords[i] || "")
    var wanted = chordToBind(chord)
    if (!wanted.key) continue
    var descriptions = []
    var ours = false
    for (var j = 0; j < binds.length; j++) {
      var bind = binds[j]
      if (!bind || typeof bind !== "object") continue
      if (Number(bind.modmask || 0) !== wanted.modmask) continue
      if (String(bind.key || "").toUpperCase() !== wanted.key) continue
      var description = String(bind.description || "")
      descriptions.push(description)
      if (description.indexOf("Switcher:") === 0) ours = true
      else if (BENIGN_BINDS.indexOf(description) === -1)
        conflicts.push({ chord: chord, description: description })
    }
    owners[chord] = descriptions
    if (!ours) missing.push(chord)
  }
  return { owners: owners, missing: missing, conflicts: conflicts }
}

// Chord, description and command values are internal constants, but escape
// them anyway: the expression is handed to a Lua parser, not a shell.
function luaString(value) {
  return '"' + String(value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n") + '"'
}

function hyprEvalForSettings(settings, dropdownEnabled, options) {
  var opts = options || {}
  var lines = []
  if (opts.layerRule !== false) lines.push(layerRuleLine())

  var chords = boundChords(settings, opts.previous)
  for (var i = 0; i < chords.length; i++)
    lines.push("hl.unbind(" + luaString(chords[i]) + ")")

  var binds = bindEntries(settings, dropdownEnabled)
  for (var j = 0; j < binds.length; j++) {
    var bind = binds[j]
    lines.push("hl.bind(" + luaString(bind.chord) + ", hl.dsp.exec_cmd(" +
      luaString(bind.command) + "), { description = " + luaString(bind.description) + " })")
  }

  return lines.join("; ")
}

// Removes every chord the plugin may own, without registering anything. Used
// when the service is destroyed, when the user switches to the static file,
// and to keep a reload from leaving stale binds behind.
function hyprUnbindEval(settings, previous) {
  var chords = boundChords(settings, previous)
  var lines = []
  for (var i = 0; i < chords.length; i++)
    lines.push("hl.unbind(" + luaString(chords[i]) + ")")
  return lines.join("; ")
}

if (typeof module !== "undefined") {
  module.exports = {
    validAddress: validAddress,
    validAppId: validAppId,
    displayScreensFor: displayScreensFor,
    safeIconName: safeIconName,
    safeIconSource: safeIconSource,
    dropdownEnabledFromShellConfig: dropdownEnabledFromShellConfig,
    parseDropdownState: parseDropdownState,
    parseClients: parseClients,
    initialIndex: initialIndex,
    shortcutPresets: shortcutPresets,
    allShortcutPresets: allShortcutPresets,
    allPresetForKey: allPresetForKey,
    defaultSettings: defaultSettings,
    presetForKey: presetForKey,
    parseSettings: parseSettings,
    serializeSettings: serializeSettings,
    luaForSettings: luaForSettings,
    boundChords: boundChords,
    activeChords: activeChords,
    parseBinds: parseBinds,
    hyprEvalForSettings: hyprEvalForSettings,
    hyprUnbindEval: hyprUnbindEval
  }
}
