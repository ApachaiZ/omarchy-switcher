#!/usr/bin/env bash
# Local check suite. CI runs the same steps without the Omarchy-only ones.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v node >/dev/null 2>&1 || {
  echo "check.sh: node is required" >&2
  exit 1
}

node --test tests/*.test.mjs
node --check Model.js
bash -n scripts/*.sh tests/*.sh
tests/static-binds.test.sh

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi

QMLINT="$(command -v qmllint || true)"
if [[ -z $QMLINT && -x /usr/lib/qt6/bin/qmllint ]]; then
  QMLINT=/usr/lib/qt6/bin/qmllint
fi
if [[ -n $QMLINT ]]; then
  "$QMLINT" ./*.qml
fi

echo "checks: ok"
