"""Package the Steam Frame ARM64 build as a .tar.gz for a GitHub release.

Run tools/build.ps1 first. The archive keeps Unix permissions, so the executable and launcher
stay runnable after extracting on the Frame:

    python tools/package_release.py v0.1.0
"""
import io
import sys
import tarfile
import time
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
FOLDER = "azads-steam-frame-experiments"
INSTALL = """Azad's Steam Frame Experiments {version}

Install on the Steam Frame
  1. In Desktop Mode, download {archive} from the GitHub release.
  2. Extract it (Dolphin: right-click > Extract > Extract here).
  3. Double-click install.py in the extracted folder and choose Execute.
     A message confirms the install.
  4. In the headset, open the Steam library > Non-Steam and launch
     "Azads_Steam_Frame_Experiments".
  You can delete the downloaded folder afterwards; the app is copied to ~/devkit-game.
  If the installer says Steam did not answer, turn on Developer Mode in Steam settings.

Update: install a newer release the same way; it replaces the old one.
Uninstall: run "python3 install.py --uninstall" from a terminal in the extracted folder.

Contents
  install.py          installer (copies the app and registers it with Steam)
  frame-lab.arm64     Godot 4.7.2 Linux ARM64 executable
  frame-lab.pck       game data (must stay next to the executable)
  launch.sh           starts the executable with SteamVR's OpenXR runtime
  vrpreferences.json  asks SteamVR for at least 90 Hz

Logs go to ~/.local/state/frame-lab/godot.log.
"""


def add_file(archive, source, name, mode):
    info = archive.gettarinfo(str(source), arcname=f"{FOLDER}/{name}")
    info.mode = mode
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    with open(source, "rb") as handle:
        archive.addfile(info, handle)


def add_text(archive, name, text, mode=0o644):
    data = text.encode("utf-8")
    info = tarfile.TarInfo(f"{FOLDER}/{name}")
    info.size = len(data)
    info.mode = mode
    info.mtime = int(time.time())
    archive.addfile(info, io.BytesIO(data))


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "dev"
    build = PROJECT / "build"
    archive_name = f"{FOLDER}-{version}-linux-arm64.tar.gz"
    sources = {
        "frame-lab.arm64": (build / "frame-lab.arm64", 0o755),
        "frame-lab.pck": (build / "frame-lab.pck", 0o644),
        "launch.sh": (PROJECT / "tools" / "launch.sh", 0o755),
        "install.py": (PROJECT / "tools" / "install.py", 0o755),
        "vrpreferences.json": (PROJECT / "vrpreferences.json", 0o644),
    }
    for name, (source, _) in sources.items():
        if not source.is_file():
            raise SystemExit(f"Missing {source}; run tools/build.ps1 first.")
    target = build / archive_name
    with tarfile.open(target, "w:gz") as archive:
        for name, (source, mode) in sources.items():
            if name in ("launch.sh", "install.py"):
                # Unix line endings, whatever the Windows checkout uses.
                add_text(archive, name, source.read_text(encoding="utf-8").replace("\r\n", "\n"), mode)
            else:
                add_file(archive, source, name, mode)
        add_text(archive, "INSTALL.txt", INSTALL.format(version=version, archive=archive_name))
    print(f"Wrote {target} ({target.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
