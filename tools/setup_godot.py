"""Install pinned official Godot binaries and export templates in user directories."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import os
from pathlib import Path
import urllib.request
import zipfile


VERSION = "4.7.2"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable"
EDITOR = f"Godot_v{VERSION}-stable_win64.exe.zip"
TEMPLATES = f"Godot_v{VERSION}-stable_export_templates.tpz"
DOWNLOADS = Path(__file__).resolve().parents[2] / "downloads" / f"godot-{VERSION}"
INSTALL = Path.home() / "Documents" / "_apps" / "Godot" / VERSION
TEMPLATE_DIR = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / f"{VERSION}.stable"


def download(name):
    destination = DOWNLOADS / name
    if not destination.exists():
        print(f"Downloading {name}", flush=True)
        temporary = destination.with_suffix(destination.suffix + ".part")
        urllib.request.urlretrieve(f"{BASE}/{name}", temporary)
        temporary.replace(destination)
    return destination


def main():
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as executor:
        list(executor.map(download, [EDITOR, TEMPLATES, "SHA512-SUMS.txt"]))
    checksums = {}
    for line in (DOWNLOADS / "SHA512-SUMS.txt").read_text().splitlines():
        parts = line.split()
        if len(parts) == 2:
            checksums[parts[1].lstrip("*")] = parts[0].lower()
    for name in [EDITOR, TEMPLATES]:
        with (DOWNLOADS / name).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha512").hexdigest()
        if actual != checksums[name]:
            raise RuntimeError(f"Official SHA-512 mismatch: {name}")
        print(f"Verified SHA-512: {name}", flush=True)
    INSTALL.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(DOWNLOADS / EDITOR) as archive:
        archive.extractall(INSTALL)
    TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(DOWNLOADS / TEMPLATES) as archive:
        for entry in archive.infolist():
            name = Path(entry.filename).name
            if name == "version.txt" or name.startswith(("linux_debug.arm64", "linux_release.arm64", "windows_debug_x86_64", "windows_release_x86_64")):
                (TEMPLATE_DIR / name).write_bytes(archive.read(entry))
                print(f"Installed template: {name}", flush=True)
    print(f"Godot editor: {INSTALL / f'Godot_v{VERSION}-stable_win64.exe'}")


if __name__ == "__main__":
    main()
