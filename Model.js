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
    var layout = config.bar && config.bar.layout
    if (!layout || typeof layout !== "object") return false
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]]
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        var id = entry && typeof entry === "object" ? String(entry.id || "") : String(entry || "")
        if (id === "apach.dropdown") return true
      }
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

function safeScreenName(value) {
  var text = String(value || "").trim()
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(text) ? text : ""
}

function defaultSettings() {
  return { version: 1, dropdownShortcut: "CTRL + TAB", followActive: true, screens: [] }
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
    return {
      version: 1,
      dropdownShortcut: presetForKey(parsed.dropdownShortcut).key,
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
  return JSON.stringify({
    version: 1,
    dropdownShortcut: presetForKey(value.dropdownShortcut).key,
    followActive: value.followActive !== false,
    screens: screens
  }, null, 2) + "\n"
}

// Generated Hyprland Lua. The inline file is intentionally small and contains
// no user data. Settings writes the same template with the chosen shortcut.
function luaForSettings(settings) {
  var preset = presetForKey((settings || defaultSettings()).dropdownShortcut)
  return [
    "-- Generated by apach.switcher. Edit the shortcut in Switcher settings.",
    'hl.layer_rule({ match = { namespace = "apach-switcher" }, blur = true, ignore_alpha = 0.15, no_anim = true })',
    "",
    'hl.unbind("ALT + TAB")',
    'hl.unbind("ALT + SHIFT + TAB")',
    'hl.unbind("' + preset.key + '")',
    'hl.unbind("' + preset.reverse + '")',
    "",
    'o.bind("ALT + TAB", "Switcher: all windows", "omarchy-shell -q apach.switcher next")',
    'o.bind("ALT + SHIFT + TAB", "Switcher: reverse windows", "omarchy-shell -q apach.switcher prev")',
    'local function switcherHasDropdown()',
    '  local file = io.open(os.getenv("HOME") .. "/.config/omarchy/shell.json", "r")',
    '  if not file then return false end',
    '  local data = file:read("*a") or ""',
    '  file:close()',
    '  return data:find(\'"apach.dropdown"\', 1, true) ~= nil',
    'end',
    'if switcherHasDropdown() then',
    '  o.bind("' + preset.key + '", "Switcher: Dropdown windows", "omarchy-shell -q apach.switcher nextDropdown")',
    '  o.bind("' + preset.reverse + '", "Switcher: reverse Dropdown windows", "omarchy-shell -q apach.switcher prevDropdown")',
    'end',
    'o.bind("SUPER + ALT + S", "Switcher: settings", "omarchy-shell -q apach.switcher settings")',
    ""
  ].join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    validAddress: validAddress,
    validAppId: validAppId,
    safeScreenName: safeScreenName,
    safeIconName: safeIconName,
    safeIconSource: safeIconSource,
    dropdownEnabledFromShellConfig: dropdownEnabledFromShellConfig,
    parseDropdownState: parseDropdownState,
    parseClients: parseClients,
    initialIndex: initialIndex,
    shortcutPresets: shortcutPresets,
    defaultSettings: defaultSettings,
    presetForKey: presetForKey,
    parseSettings: parseSettings,
    serializeSettings: serializeSettings,
    luaForSettings: luaForSettings
  }
}
