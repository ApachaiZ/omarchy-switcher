import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// Owns the Hyprland keyboard integration. Runtime mode registers binds and the
// layer rule with `hyprctl eval`, and re-applies them after every config
// reload (Hyprland keeps no runtime state across reloads). A static
// ~/.config/hypr/switcher.lua required from the user's config takes
// precedence, in which case this component stays out of the keys entirely.
Item {
  id: root

  property var settings: ({})
  property bool dropdownEnabled: false
  property bool settingsLoaded: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string staticPath: home + "/.config/hypr/switcher.lua"
  readonly property string hyprlandPath: home + "/.config/hypr/hyprland.lua"
  readonly property string bindingsPath: home + "/.config/hypr/bindings.lua"

  property bool staticFilePresent: false
  property bool staticProbed: false
  property bool hyprlandRequires: false
  property bool hyprlandProbed: false
  property bool bindingsRequires: false
  property bool bindingsProbed: false
  readonly property bool probed: staticProbed && hyprlandProbed && bindingsProbed

  readonly property bool requirePresent: hyprlandRequires || bindingsRequires
  readonly property bool legacy: staticFilePresent && requirePresent
  readonly property string mode: legacy ? "static" : "runtime"

  property bool registered: false
  property string status: "idle"   // idle | pending | ok | error
  property string lastError: ""
  property var conflicts: []

  property var applied: ({})
  property string appliedFingerprint: ""
  property int attempts: 0
  property bool pendingVerify: false
  property bool pendingBinds: false
  property bool started: false

  // One eval at a time: every `hyprctl eval` is a process, and running them
  // concurrently would race the unbind/bind sequence.
  property string evalCode: ""
  property bool evalRunning: false
  property string queuedCode: ""
  property bool queuedVerify: false

  function fingerprint(value) {
    var s = value || settings || ({})
    return JSON.stringify({
      all: String(s.allShortcut || ""),
      dropdown: String(s.dropdownShortcut || ""),
      enabled: dropdownEnabled
    })
  }

  function apply(options) {
    var opts = options || {}
    if (!settingsLoaded || !probed || legacy) return
    var current = settings
    if (!current || typeof current !== "object") current = Model.defaultSettings()

    var print = fingerprint(current)
    if (print === appliedFingerprint && registered && opts.retry !== true) {
      if (opts.verify === true) verify()
      return
    }

    appliedFingerprint = print
    var code = Model.hyprEvalForSettings(current, dropdownEnabled, {
      layerRule: opts.reset === true || !registered,
      previous: applied
    })
    applied = {
      allShortcut: String(current.allShortcut || ""),
      dropdownShortcut: String(current.dropdownShortcut || "")
    }
    evaluate(code, opts.verify === true)
  }

  function evaluate(code, verifyAfter) {
    if (evalRunning) {
      // Coalesce: only the latest requested expression matters.
      queuedCode = code
      queuedVerify = queuedVerify || verifyAfter
      return
    }
    evalCode = code
    pendingVerify = verifyAfter
    evalRunning = true
    status = "pending"
    evalProc.running = true
  }

  function drain() {
    if (!queuedCode) return
    var code = queuedCode
    var verifyAfter = queuedVerify
    queuedCode = ""
    queuedVerify = false
    evaluate(code, verifyAfter)
  }

  // Compare the live bind table with the chords we expect. This is also where
  // conflicts with other bindings are detected, and where a registration that
  // did not land is retried exactly once.
  function verify() {
    if (legacy || !registered) return
    if (bindsProc.running) {
      pendingBinds = true
      return
    }
    bindsProc.running = true
  }

  function refreshConflicts() {
    if (legacy) {
      conflicts = []
      return
    }
    verify()
  }

  function diagnostics() {
    return {
      mode: mode,
      status: status,
      registered: registered,
      staticFile: staticFilePresent,
      requireLine: requirePresent,
      conflicts: conflicts.length,
      lastError: lastError
    }
  }

  function startIfReady() {
    if (started || !settingsLoaded || !probed) return
    started = true
    attempts = 0
    if (!legacy) apply({ reset: true, verify: true })
  }

  function settingsUpdated() {
    attempts = 0
    if (started) apply()
  }

  onSettingsLoadedChanged: startIfReady()
  onProbedChanged: startIfReady()
  onSettingsChanged: settingsUpdated()
  onDropdownEnabledChanged: settingsUpdated()

  onLegacyChanged: {
    if (!started) return
    if (legacy) {
      conflicts = []
      if (registered) {
        registered = false
        appliedFingerprint = ""
        applied = {}
        status = "idle"
        // Let the static file load and take over the chords.
        reloadProc.running = true
      }
    } else {
      attempts = 0
      apply({ reset: true, verify: true })
    }
  }

  // Hyprland drops runtime binds and layer rules on every config reload, so
  // re-register as soon as the user's config has been applied again.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "configreloaded") return
      if (root.legacy) return
      // Coalesce bursts: a theme apply or a script can reload the config more
      // than once in a row.
      reloadDebounce.restart()
    }
  }

  Timer {
    id: reloadDebounce
    interval: 150
    repeat: false
    onTriggered: {
      root.attempts = 0
      root.apply({ reset: true, verify: true, retry: true })
      root.refreshConflicts()
    }
  }

  Component.onDestruction: {
    if (legacy || !registered) return
    Quickshell.execDetached(["hyprctl", "eval", Model.hyprUnbindEval(settings, applied)])
  }

  Process {
    id: evalProc
    command: ["hyprctl", "eval", root.evalCode]
    onExited: function(exitCode) {
      root.evalRunning = false
      // StdioCollector.text is a property in Quickshell, not a method.
      var out = String(evalOut.text).trim()
      var err = String(evalErr.text).trim()
      var failed = exitCode !== 0 || out.indexOf("error:") === 0
      if (failed) {
        root.status = "error"
        // Keep it short: Hyprland errors can echo the expression back.
        root.lastError = String(err || out || ("hyprctl exited " + exitCode)).slice(0, 200)
        root.registered = false
        root.appliedFingerprint = ""
      } else {
        root.status = "ok"
        root.lastError = ""
        root.registered = true
        if (root.pendingVerify) {
          root.pendingVerify = false
          root.verify()
        }
      }
      root.drain()
    }
    stdout: StdioCollector {
      id: evalOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: evalErr
      waitForEnd: true
    }
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var result = Model.parseBinds(String(bindsOut.text),
          Model.activeChords(root.settings, root.dropdownEnabled))
        root.conflicts = result.conflicts
        if (result.missing.length > 0 && root.attempts < 1) {
          root.attempts++
          root.apply({ reset: true, verify: true, retry: true })
        }
      }
      if (root.pendingBinds) {
        root.pendingBinds = false
        root.verify()
      }
    }
    stdout: StdioCollector {
      id: bindsOut
      waitForEnd: true
    }
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
  }

  FileView {
    id: staticFile
    path: root.staticPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.staticFilePresent = true
      root.staticProbed = true
    }
    onLoadFailed: {
      root.staticFilePresent = false
      root.staticProbed = true
    }
    onFileChanged: reload()
  }

  FileView {
    id: hyprlandFile
    path: root.hyprlandPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.hyprlandRequires = root.requiresSwitcher(text())
      root.hyprlandProbed = true
    }
    onLoadFailed: {
      root.hyprlandRequires = false
      root.hyprlandProbed = true
    }
    onFileChanged: reload()
  }

  FileView {
    id: bindingsFile
    path: root.bindingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.bindingsRequires = root.requiresSwitcher(text())
      root.bindingsProbed = true
    }
    onLoadFailed: {
      root.bindingsRequires = false
      root.bindingsProbed = true
    }
    onFileChanged: reload()
  }

  function requiresSwitcher(raw) {
    return /require\s*\(\s*["']hypr\.switcher["']\s*\)/.test(String(raw || ""))
  }
}
