#!/usr/bin/env bash
# content-manifest.sh ROOT [VOLATILE_FILE] - wrapper; see content-manifest.py (idea#322).
exec python3 "$(dirname "$0")/content-manifest.py" "$@"
