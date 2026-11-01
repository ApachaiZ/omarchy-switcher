import test from "node:test"
import assert from "node:assert/strict"
import { existsSync, lstatSync, readFileSync, readdirSync, statSync } from "node:fs"
import { join } from "node:path"

// Mirrors the checks in omarchy-plugin-validate so CI catches a manifest the
// running shell would reject, without needing an Omarchy install.
const manifest = JSON.parse(readFileSync("manifest.json", "utf8"))

test("manifest matches the Omarchy plugin schema", () => {
  assert.equal(manifest.schemaVersion, 1)
  for (const field of ["id", "name", "version", "kinds", "entryPoints"])
    assert.ok(field in manifest, `missing ${field}`)

  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.equal(manifest.id.includes(".."), false)
  assert.equal(manifest.id.startsWith("omarchy."), false)
  assert.ok(Array.isArray(manifest.kinds) && manifest.kinds.length > 0)
  assert.equal(typeof manifest.entryPoints, "object")
  assert.match(String(manifest.version), /^\d+\.\d+\.\d+/)
  if ("keepLoaded" in manifest) assert.equal(typeof manifest.keepLoaded, "boolean")

  for (const key of ["install", "postInstall", "hooks"])
    assert.equal(key in manifest, false, `hooks are not part of the plugin contract: ${key}`)
})

test("every entry point is a safe relative file that exists", () => {
  for (const entry of Object.values(manifest.entryPoints)) {
    assert.equal(typeof entry, "string")
    assert.ok(entry.length > 0)
    assert.equal(entry.startsWith("/"), false)
    assert.equal(entry.includes(".."), false)
    assert.equal(entry.includes("\n"), false)
    assert.ok(statSync(entry).isFile(), `entry point not found: ${entry}`)
  }

  const required = {
    bar: "bar",
    "bar-widget": "barWidget",
    menu: "menu",
    overlay: "overlay",
    panel: "panel",
    service: "service"
  }
  for (const kind of manifest.kinds) {
    const key = required[kind]
    if (key) assert.ok(key in manifest.entryPoints, `kind ${kind} needs entryPoints.${key}`)
  }
})

test("the plugin folder contains no symlinks or install scripts", () => {
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (name === ".git" || name === "node_modules") continue
      const path = join(dir, name)
      const stats = lstatSync(path)
      assert.equal(stats.isSymbolicLink(), false, `symlink: ${path}`)
      if (stats.isDirectory()) walk(path)
    }
  }
  walk(".")

  for (const name of ["install.sh", "uninstall.sh"])
    assert.equal(existsSync(name), false, `${name} must not ship in a plugin`)
})
