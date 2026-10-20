#!/usr/bin/env python3
"""Install Azad's Steam Frame Experiments on this Steam Frame: double-click this file.

Copies the app into ~/devkit-game and registers it with the running Steam client the same way
Valve's devkit tools do (config files plus a command over ~/.steam/steam.pipe). It then shows up in
the Steam library under Non-Steam. Run with --uninstall to remove it.
Self-contained: needs only Python 3 and a running Steam client, not the PC devkit tools.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import quote_plus

GAMEID = "Azads_Steam_Frame_Experiments"
TITLE = "Azad's Steam Frame Experiments"
FILES = ["frame-lab.arm64", "frame-lab.pck", "launch.sh", "vrpreferences.json"]
HOME = Path.home()
DEVKIT = HOME / "devkit-game"
STEAM = HOME / ".steam"


def tell(message, error=False):
    """Double-clicked scripts have no terminal, so also show a dialog or notification."""
    print(message, file=sys.stderr if error else sys.stdout)
    if shutil.which("kdialog"):
        subprocess.run(["kdialog", "--title", TITLE, "--error" if error else "--msgbox", message])
    elif shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", TITLE, TITLE, message])


def steam_running():
    try:
        os.kill(int((STEAM / "steam.pid").read_text().strip()), 0)
        return (STEAM / "steam.pipe").exists() and (STEAM / "steam.token").exists()
    except (OSError, ValueError):
        return False


def steam_command(command, timeout=20):
    """Send a devkit command to Steam and wait for its file response (Valve's devkit protocol)."""
    with tempfile.TemporaryDirectory(prefix="frame-experiments-") as folder:
        response = Path(folder) / "response"
        token = (STEAM / "steam.token").read_text().strip()
        line = f"devkit-1 steam://devkit-1/{token}/{command}&response={quote_plus(str(response))}\n"
        with open(STEAM / "steam.pipe", "wb", 0) as pipe:
            pipe.write(line.encode("utf-8"))
        error = Path(f"{response}.error")
        lock = Path(f"{response}.lock")
        for _ in range(timeout):
            time.sleep(1)
            if error.exists():
                raise RuntimeError(error.read_text().strip() or "Steam reported an error")
            if response.exists() and not lock.exists():
                return response.read_text().strip()
    raise TimeoutError("Steam did not answer")


def install(source):
    missing = [name for name in FILES if not (source / name).is_file()]
    if missing:
        raise RuntimeError(f"Missing {', '.join(missing)} next to install.py; extract the whole archive first.")
    target = DEVKIT / GAMEID
    staging = DEVKIT / f".{GAMEID}.installing"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    for name in FILES:
        shutil.copy2(source / name, staging / name)
        mode = 0o755 if name in ("frame-lab.arm64", "launch.sh") else 0o644
        (staging / name).chmod(mode)
    shutil.rmtree(target, ignore_errors=True)
    staging.rename(target)
    (DEVKIT / f"{GAMEID}-argv.json").write_text(json.dumps(["./launch.sh"]))
    (DEVKIT / f"{GAMEID}-settings.json").write_text(json.dumps({"compat_tool": "SteamLinuxRuntime_4-arm64", "steam_play": "0"}))
    result = steam_command(f"create-shortcut?gameid={GAMEID}&directory={quote_plus(str(DEVKIT))}")
    print(f"Steam: {result}")


def uninstall():
    if steam_running():
        try:
            print(f"Steam: {steam_command(f'delete-shortcut?gameid={GAMEID}')}")
        except (RuntimeError, TimeoutError) as error:
            print(f"Steam did not remove the shortcut: {error}", file=sys.stderr)
    shutil.rmtree(DEVKIT / GAMEID, ignore_errors=True)
    for suffix in ("argv", "settings", "env"):
        (DEVKIT / f"{GAMEID}-{suffix}.json").unlink(missing_ok=True)


def main():
    if not steam_running():
        tell("Steam is not running. Start Steam (Desktop Mode or the headset view) and run this again.", error=True)
        return 1
    try:
        if "--uninstall" in sys.argv:
            uninstall()
            tell(f"{TITLE} was removed.")
        else:
            install(Path(__file__).resolve().parent)
            tell(f"{TITLE} is installed.\n\nLaunch it from the Steam library under Non-Steam.")
    except (OSError, RuntimeError, TimeoutError) as error:
        tell(f"Install failed: {error}\n\nIf Steam did not answer, turn on Developer Mode in Steam settings and try again.", error=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
