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
  assert.equal(all.length, 2)
  assert.equal(all[0].addr, "0xAAA1")
  assert.equal(all[0].dropdown, true)
  assert.equal(all[0].hidden, true)
  assert.equal(all[1].title, "Later")
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
  assert.equal(Model.parseSettings('{"dropdownShortcut":"SUPER + TAB"}').dropdownShortcut, "SUPER + TAB")
  assert.equal(Model.parseSettings('{"dropdownShortcut":"CTRL + F12"}').dropdownShortcut, "CTRL + TAB")
  assert.equal(Model.parseSettings("not json").dropdownShortcut, "CTRL + TAB")
  assert.equal(Model.presetForKey("ctrl + space").key, "CTRL + SPACE")
})

test("generated Lua contains the selected Dropdown shortcut and layer rule", () => {
  const lua = Model.luaForSettings({ dropdownShortcut: "SUPER + TAB" })
  assert.match(lua, /namespace = "apach-switcher"/)
  assert.match(lua, /o\.bind\("SUPER \+ TAB"/)
  assert.match(lua, /o\.bind\("SUPER \+ SHIFT \+ TAB"/)
  assert.match(lua, /ALT \+ TAB/)
  assert.match(lua, /apach\.switcher settings/)
})
