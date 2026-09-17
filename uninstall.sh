#!/usr/bin/env bash
# Thin wrapper: uninstall the pack via install.sh.
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/install.sh" uninstall "$@"
