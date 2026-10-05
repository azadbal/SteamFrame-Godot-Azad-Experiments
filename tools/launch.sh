#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p "$HOME/.local/state/frame-lab"
export XR_RUNTIME_JSON=/opt/steamvr/steamxr_linuxarm64.json
exec ./frame-lab.arm64 --xr-mode on --log-file "$HOME/.local/state/frame-lab/godot.log" "$@"
