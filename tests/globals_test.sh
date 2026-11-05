#!/usr/bin/env bash
# A missing `local` is invisible to `luac -p` and to a config that only *loads*:
# the name silently becomes a nil global and fails the first time a callback
# touches it. That is exactly how a deleted `local X_MODE_STATE` and a deleted
# `as_list` reached a live session -- the config parsed, the suite's smoke load
# passed, and the desktop answered "attempt to concatenate a nil value".
#
# The check is on the bytecode: a read of a global the file never assigns is an
# undeclared name, since locals never show up as GETTABUP.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
checker="$here/globals.lua"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

# Red first: without the checker there is nothing to run.
if [ ! -f "$checker" ]; then
  echo "FAIL globals: $checker does not exist"
  exit 1
fi

cat >"$tmp/bad.lua" <<'EOF'
local function helper()
  return 1
end

local function uses_missing()
  -- `missing_table` is never declared and never assigned: a stray global.
  return missing_table .. "x" .. helper()
end

return uses_missing()
EOF

if lua "$checker" "$tmp/bad.lua" >"$tmp/bad.out" 2>&1; then
  echo "FAIL globals: an undeclared global was not reported"
  sed 's/^/    /' "$tmp/bad.out"
  fail=1
else
  grep -q missing_table "$tmp/bad.out" || {
    echo "FAIL globals: the report does not name missing_table"
    sed 's/^/    /' "$tmp/bad.out"
    fail=1
  }
fi

cat >"$tmp/good.lua" <<'EOF'
local hl = { unbind = function() end }
local declared = "x"
local function helper()
  return declared
end

globally_assigned = helper()

local function uses_globals()
  return hl.unbind ~= nil and globally_assigned ~= nil and tostring(1) == "1"
end

return uses_globals()
EOF

if ! lua "$checker" "$tmp/good.lua" >"$tmp/good.out" 2>&1; then
  echo "FAIL globals: a clean file was rejected"
  sed 's/^/    /' "$tmp/good.out"
  fail=1
fi

# The pack itself has to be clean, which is the point of the check.
if ! lua "$checker" "$here"/../hypr/x-mode/*.lua >"$tmp/pack.out" 2>&1; then
  echo "FAIL globals: the pack has undeclared globals"
  sed 's/^/    /' "$tmp/pack.out"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok   globals"
