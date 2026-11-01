import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

// Window titles, app names and Dropdown state are untrusted input. Keep the
// same regression guard used by Dropdown/Quay: every Text is plain text, and
// no screen capture or shell command may be introduced into the service.
const files = ["Service.qml", "Model.js"]

function blockEnd(source, openBrace) {
  let depth = 0
  for (let i = openBrace; i < source.length; i++) {
    const ch = source[i]
    if (ch === "/" && source[i + 1] === "/") {
      const newline = source.indexOf("\n", i)
      i = newline === -1 ? source.length : newline
      continue
    }
    if (ch === "/" && source[i + 1] === "*") {
      const close = source.indexOf("*/", i + 2)
      i = close === -1 ? source.length : close + 1
      continue
    }
    if (ch === '"' || ch === "'") {
      const quote = ch
      for (i++; i < source.length; i++) {
        if (source[i] === "\\") {
          i++
          continue
        }
        if (source[i] === quote) break
      }
      continue
    }
    if (ch === "{") depth++
    else if (ch === "}") {
      depth--
      if (depth === 0) return i
    }
  }
  return -1
}

function textBlocks(file) {
  const source = readFileSync(file, "utf8")
  const blocks = []
  const pattern = /^[ \t]*Text[ \t]*\{[ \t]*$/gm
  let match
  while ((match = pattern.exec(source)) !== null) {
    const open = source.indexOf("{", match.index)
    const close = blockEnd(source, open)
    if (close === -1) continue
    blocks.push({
      file,
      line: source.slice(0, match.index).split("\n").length,
      text: source.slice(match.index, close + 1)
    })
  }
  return blocks
}

const blocks = textBlocks("Service.qml")

test("every QML Text element renders plain text", () => {
  const failures = blocks
    .filter((block) => !/^\s*textFormat\s*:\s*Text\.PlainText\s*$/m.test(block.text))
    .map((block) => `${block.file}:${block.line}`)
  assert.deepEqual(failures, [], "Text elements must set Text.PlainText")
})

test("rich text and screen capture are never requested", () => {
  for (const file of files) {
    const source = readFileSync(file, "utf8")
    assert.equal(/Text\.(AutoText|RichText|StyledText)/.test(source), false, file)
    assert.equal(/ScreencopyView|ScreenCopy/.test(source), false, file)
    assert.equal(/console\.(log|info|debug)/.test(source), false, file)
    assert.equal(/"?(sh|bash)"?\s*,\s*"-c"/.test(source), false, file)
  }
})

test("no remote URL is embedded in the service", () => {
  for (const file of files) {
    assert.equal(/https?:\/\//.test(readFileSync(file, "utf8")), false, file)
  }
})
