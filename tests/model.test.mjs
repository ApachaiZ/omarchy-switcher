import test from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const Model = require("../Model.js")

test("window addresses and Dropdown app ids are validated", () => {
  assert.equal(Model.validAddress("0x5593b095cac0"), "0x5593b095cac0")
  assert.equal(Model.validAddress("5593b095cac0"), "")
  assert.equal(Model.validAddress("0xzz"), "")
  assert.equal(Model.validAppId("system.terminal"), "system.terminal")
  assert.equal(Model.validAppId("Discord"), "Discord")
  assert.equal(Model.validAppId("../bad"), "")
  assert.equal(Model.validAppId("a b"), "")
})

test("Dropdown state maps addresses to validated app ids", () => {
  const raw = JSON.stringify({
    apps: {
      "system.terminal": { address: "0xAAA1", class: "apach.dropdown.terminal", hidden: true },
      Discord: { address: "0xBBB2", class: "brave-discord", hidden: false },
      bad: { address: "../../etc", class: "x" }
    }
  })
  const map = Model.parseDropdownState(raw)
  assert.deepEqual(map["0xaaa1"], { appId: "system.terminal", cls: "apach.dropdown.terminal", hidden: true })
  assert.deepEqual(map["0xbbb2"], { appId: "Discord", cls: "brave-discord", hidden: false })
  assert.equal(Object.keys(map).length, 2)
  assert.deepEqual(Model.parseDropdownState("not json"), {})
})

test("client parsing filters, sorts and identifies Dropdown windows", () => {
  const dropdown = { "0xaaa1": { appId: "system.terminal", cls: "apach.dropdown.terminal", hidden: true } }
  const raw = JSON.stringify([
    { address: "0xBBB2", class: "brave-browser", title: "Later", mapped: true, focusHistoryID: 3, workspace: { name: "2" }, tags: [] },
    { address: "0xAAA1", class: "apach.dropdown.terminal", title: "Terminal", mapped: true, focusHistoryID: 0, workspace: { name: "special:special" }, tags: ["dropdown-hidden"] },
    { address: "0xCCC3", class: "unmapped", title: "No", mapped: false, focusHistoryID: 1, workspace: { name: "1" }, tags: [] },
    { address: "0xDDD4", class: "apach.switcher", title: "Self", mapped: true, focusHistoryID: 1, workspace: { name: "1" }, tags: [] }
  ])
  const all = Model.parseClients(raw, dropdown, "all")
  assert.equal(all.length, 1)
  assert.equal(all[0].addr, "0xBBB2")
  assert.equal(all[0].title, "Later")
  assert.equal(all[0].dropdown, false)
  const only = Model.parseClients(raw, dropdown, "dropdown")
  assert.equal(only.length, 1)
  assert.equal(only[0].appId, "system.terminal")
})

test("initial selection is the previous window, reverse starts at the end", () => {
  assert.equal(Model.initialIndex(0, false), -1)
  assert.equal(Model.initialIndex(1, false), 0)
  assert.equal(Model.initialIndex(4, false), 1)
  assert.equal(Model.initialIndex(4, true), 3)
})

test("shortcut settings are bounded to known presets", () => {
  assert.equal(Model.defaultSettings().dropdownShortcut, "CTRL + TAB")
  assert.equal(Model.defaultSettings().allShortcut, "ALT + TAB")
  assert.equal(Model.parseSettings('{"dropdownShortcut":"SUPER + TAB"}').dropdownShortcut, "SUPER + TAB")
  assert.equal(Model.parseSettings('{"dropdownShortcut":"CTRL + F12"}').dropdownShortcut, "CTRL + TAB")
  assert.equal(Model.parseSettings("not json").dropdownShortcut, "CTRL + TAB")
  assert.equal(Model.presetForKey("ctrl + space").key, "CTRL + SPACE")
  assert.equal(Model.allPresetForKey("alt + grave").key, "ALT + GRAVE")
  assert.equal(Model.allPresetForKey("SUPER + TAB").key, "ALT + TAB")
})

test("all-windows and Dropdown shortcuts never collide", () => {
  const parsed = Model.parseSettings(JSON.stringify({
    allShortcut: "ALT + GRAVE",
    dropdownShortcut: "CTRL + SPACE"
  }))
  assert.equal(parsed.allShortcut, "ALT + GRAVE")
  assert.equal(parsed.dropdownShortcut, "CTRL + SPACE")

  const out = JSON.parse(Model.serializeSettings({
    allShortcut: "ALT + TAB",
    dropdownShortcut: "CTRL + TAB"
  }))
  assert.equal(out.allShortcut, "ALT + TAB")
  assert.equal(out.dropdownShortcut, "CTRL + TAB")
  assert.equal(JSON.parse(Model.serializeSettings(Model.defaultSettings())).version, 1)
})

test("generated Lua contains the selected Dropdown shortcut and layer rule", () => {
  const lua = Model.luaForSettings({ dropdownShortcut: "SUPER + TAB" })
  assert.match(lua, /namespace = "apach-switcher"/)
  assert.match(lua, /o\.bind\("SUPER \+ TAB"/)
  assert.match(lua, /o\.bind\("SUPER \+ SHIFT \+ TAB"/)
  assert.match(lua, /ALT \+ TAB/)
  // Settings open from inside the overlay (Alt+S / Ctrl+S), not from a
  // global chord that would shadow Omarchy's scratchpad bind.
  assert.doesNotMatch(lua, /Switcher: settings/)
  assert.doesNotMatch(lua, /SUPER \+ ALT \+ S/)
})

test("runtime eval unbinds before binding and only binds Dropdown when enabled", () => {
  const noDropdown = Model.hyprEvalForSettings({ dropdownShortcut: "SUPER + TAB" }, false, { layerRule: false })
  assert.equal(noDropdown.includes("\n"), false)
  assert.doesNotMatch(noDropdown, /layer_rule/)
  assert.match(noDropdown, /hl\.unbind\("ALT \+ TAB"\)/)
  assert.match(noDropdown, /hl\.unbind\("SUPER \+ TAB"\)/)
  assert.match(noDropdown, /hl\.bind\("ALT \+ TAB", hl\.dsp\.exec_cmd\("omarchy-shell -q apach\.switcher next"\), \{ description = "Switcher: all windows" \}\)/)
  assert.doesNotMatch(noDropdown, /hl\.bind\("SUPER \+ TAB"/)
  assert.doesNotMatch(noDropdown, /nextDropdown|prevDropdown/)
  assert.ok(noDropdown.indexOf("hl.unbind") < noDropdown.indexOf("hl.bind"))

  const withDropdown = Model.hyprEvalForSettings({ dropdownShortcut: "SUPER + TAB" }, true)
  assert.match(withDropdown, /hl\.layer_rule/)
  assert.match(withDropdown, /hl\.bind\("SUPER \+ TAB".*nextDropdown/)
  assert.match(withDropdown, /hl\.bind\("SUPER \+ SHIFT \+ TAB".*prevDropdown/)
  assert.doesNotMatch(withDropdown, /Switcher: settings/)

  // Changing the preset leaves no stale runtime bind behind.
  const switched = Model.hyprEvalForSettings({ dropdownShortcut: "SUPER + TAB" }, true, {
    layerRule: false,
    previous: { allShortcut: "ALT + TAB", dropdownShortcut: "CTRL + TAB" }
  })
  assert.match(switched, /hl\.unbind\("CTRL \+ TAB"\)/)
  assert.match(switched, /hl\.unbind\("CTRL \+ SHIFT \+ TAB"\)/)
  assert.equal(Model.boundChords(
    { dropdownShortcut: "SUPER + TAB" },
    { allShortcut: "ALT + TAB", dropdownShortcut: "CTRL + TAB" }
  ).length, 6)
})

test("all-windows shortcut drives the first binds and its own chords", () => {
  const settings = { allShortcut: "ALT + GRAVE", dropdownShortcut: "CTRL + TAB" }
  const evalCode = Model.hyprEvalForSettings(settings, false, { layerRule: false })
  assert.match(evalCode, /hl\.bind\("ALT \+ GRAVE".*all windows/)
  assert.match(evalCode, /hl\.bind\("ALT \+ SHIFT \+ GRAVE".*reverse windows/)
  assert.doesNotMatch(evalCode, /hl\.bind\("ALT \+ TAB"/)
  assert.deepEqual(Model.activeChords(settings, false), ["ALT + GRAVE", "ALT + SHIFT + GRAVE"])
  assert.deepEqual(Model.activeChords(settings, true),
    ["ALT + GRAVE", "ALT + SHIFT + GRAVE", "CTRL + TAB", "CTRL + SHIFT + TAB"])
})

test("live bind parsing reports missing shortcuts and real conflicts", () => {
  const binds = [
    { modmask: 8, key: "TAB", description: "Focus on next window" },
    { modmask: 8, key: "TAB", description: "Switcher: all windows" },
    { modmask: 9, key: "TAB", description: "Switcher: reverse windows" },
    { modmask: 4, key: "TAB", description: "Terminal palette" },
    { modmask: 4, key: "TAB", description: "Switcher: Dropdown windows" },
    { modmask: 5, key: "TAB", description: "Switcher: reverse Dropdown windows" }
  ]
  const chords = ["ALT + TAB", "ALT + SHIFT + TAB", "CTRL + TAB", "CTRL + SHIFT + TAB"]
  const result = Model.parseBinds(JSON.stringify(binds), chords)
  assert.deepEqual(result.missing, [])
  assert.deepEqual(result.conflicts, [{ chord: "CTRL + TAB", description: "Terminal palette" }])
  assert.deepEqual(result.owners["ALT + TAB"], ["Focus on next window", "Switcher: all windows"])

  const gone = Model.parseBinds(JSON.stringify(binds.slice(0, 1)), chords)
  assert.deepEqual(gone.missing, chords)
  assert.deepEqual(Model.parseBinds("not json", chords).missing, chords)

  const grave = Model.parseBinds(JSON.stringify([
    { modmask: 8, key: "GRAVE", description: "Switcher: all windows" },
    { modmask: 9, key: "GRAVE", description: "Switcher: reverse windows" }
  ]), ["ALT + GRAVE", "ALT + SHIFT + GRAVE"])
  assert.deepEqual(grave.missing, [])
})

test("runtime unbind removes every chord the plugin may own", () => {
  const unbind = Model.hyprUnbindEval({ dropdownShortcut: "CTRL + SPACE" })
  assert.equal(unbind.includes("\n"), false)
  assert.doesNotMatch(unbind, /hl\.bind/)
  for (const chord of ["ALT + TAB", "ALT + SHIFT + TAB", "CTRL + SPACE", "CTRL + SHIFT + SPACE"])
    assert.match(unbind, new RegExp(`hl\\.unbind\\("${chord.replace(/[+]/g, "\\+")}"\\)`))
  // The global settings chord is gone on purpose: Omarchy uses it for the
  // scratchpad, and settings are reachable with Alt+S inside the overlay.
  assert.doesNotMatch(unbind, /SUPER \+ ALT \+ S/)
  assert.equal(Model.boundChords({ dropdownShortcut: "CTRL + SPACE" }).length, 4)
})

test("icon names and sources are restricted to local values", () => {
  assert.equal(Model.safeIconName("firefox"), "firefox")
  assert.equal(Model.safeIconName("org.gnome.Nautilus"), "org.gnome.Nautilus")
  assert.equal(Model.safeIconName("../../etc/passwd"), "")
  assert.equal(Model.safeIconName("https://tracker.example/x.png"), "")
  assert.equal(Model.safeIconName("/tmp/icon.png"), "")
  assert.equal(Model.safeIconSource("file:///tmp/icon.png"), "file:///tmp/icon.png")
  assert.equal(Model.safeIconSource("/tmp/icon.png"), "/tmp/icon.png")
  assert.equal(Model.safeIconSource("image://provider/icon"), "image://provider/icon")
  assert.equal(Model.safeIconSource("https://tracker.example/x.png"), "")
  assert.equal(Model.safeIconSource("data:image/png;base64,AAAA"), "")
})

test("screen selection settings are validated and serialized", () => {
  const parsed = Model.parseSettings(JSON.stringify({
    dropdownShortcut: "CTRL + TAB",
    followActive: false,
    screens: ["HDMI-A-1", "HDMI-A-2", "HDMI-A-1", "../bad", "eDP-1"]
  }))
  assert.equal(parsed.followActive, false)
  assert.deepEqual(parsed.screens, ["HDMI-A-1", "HDMI-A-2", "eDP-1"])
  assert.equal(Model.parseSettings("{}").followActive, true)
  assert.deepEqual(Model.parseSettings("{}").screens, [])
  const out = JSON.parse(Model.serializeSettings(parsed))
  assert.equal(out.followActive, false)
  assert.deepEqual(out.screens, ["HDMI-A-1", "HDMI-A-2", "eDP-1"])
})

test("Dropdown is detected from the bar layout or the enabled plugin list", () => {
  const enabled = JSON.stringify({ bar: { layout: { center: [{ id: "apach.dropdown" }] } } })
  assert.equal(Model.dropdownEnabledFromShellConfig(enabled), true)
  assert.equal(Model.dropdownEnabledFromShellConfig(JSON.stringify({ bar: { layout: { right: [{ id: "apach.dropdown" }] } } })), true)
  assert.equal(Model.dropdownEnabledFromShellConfig(JSON.stringify({ bar: { layout: { center: [] } } })), false)
  assert.equal(Model.dropdownEnabledFromShellConfig(JSON.stringify({ bar: { layout: { center: [{ id: "apach.dropdown" }] } }, disabledPlugins: ["apach.dropdown"] })), false)
  assert.equal(Model.dropdownEnabledFromShellConfig("not json"), false)
  // Service-only Dropdown: enabled, but not placed in the bar.
  assert.equal(Model.dropdownEnabledFromShellConfig(JSON.stringify({
    plugins: [{ id: "apach.dropdown" }]
  })), true)
  assert.equal(Model.dropdownEnabledFromShellConfig(JSON.stringify({
    plugins: [{ id: "apach.dropdown" }],
    disabledPlugins: ["apach.dropdown"]
  })), false)
})

test("static and runtime generators publish the same bind table", () => {
  const settings = { allShortcut: "ALT + TAB", dropdownShortcut: "CTRL + SPACE" }
  const lua = Model.luaForSettings(settings)
  const evalCode = Model.hyprEvalForSettings(settings, true, { layerRule: false })
  const luaBinds = [...lua.matchAll(/o\.bind\("([^"]+)", "([^"]+)"/g)].map((m) => `${m[1]}|${m[2]}`)
  const evalBinds = [...evalCode.matchAll(/hl\.bind\("([^"]+)".*?description = "([^"]+)"/g)]
    .map((m) => `${m[1]}|${m[2]}`)
  assert.deepEqual(evalBinds, luaBinds)
  assert.equal(luaBinds.length, 4)
})

test("generated expressions only contain the validated preset table", () => {
  const injected = {
    allShortcut: 'ALT + TAB"); os.execute("rm -rf /',
    dropdownShortcut: '"; error("boom'
  }
  const code = Model.hyprEvalForSettings(injected, true, { layerRule: true, previous: null })
  assert.doesNotMatch(code, /os\.execute|rm -rf|error\("boom/)
  assert.match(code, /hl\.bind\("ALT \+ TAB"/)
  assert.match(code, /hl\.bind\("CTRL \+ TAB"/)
  assert.match(code, /hl\.unbind\("ALT \+ TAB"\)/)
  assert.doesNotMatch(code, /\n/)
})
