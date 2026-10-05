"""Upload Frame Lab and register it using the Frame's existing Steam devkit tools."""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import shlex
import sys


PROJECT = Path(__file__).resolve().parents[1]
# Reuse this workspace's SSH dependency installation; normal pip also works.
sys.path.insert(0, str(PROJECT.parent / ".tools" / "ssh"))
import paramiko


def run(client, command):
    _, stdout, stderr = client.exec_command(command, timeout=45)
    output = stdout.read().decode("utf-8", errors="replace")
    error = stderr.read().decode("utf-8", errors="replace")
    status = stdout.channel.recv_exit_status()
    if output:
        print(output.rstrip(), flush=True)
    if error:
        print(error.rstrip(), file=sys.stderr, flush=True)
    if status:
        raise RuntimeError(f"Remote command failed ({status})")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launch", action="store_true")
    args = parser.parse_args()
    files = [PROJECT / "build" / name for name in ("frame-lab.arm64", "frame-lab.pck")]
    files.append(PROJECT / "tools" / "launch.sh")
    for path in files:
        if not path.is_file():
            raise RuntimeError(f"Build first; missing {path}")
    password = os.environ.get("FRAME_SSH_PASSWORD") or getpass.getpass("Frame SSH password: ")
    with paramiko.SSHClient() as client:
        client.load_system_host_keys(str(Path.home() / ".ssh" / "known_hosts"))
        client.connect("frame", username="steamos", password=password,
                       look_for_keys=False, allow_agent=False, timeout=10, auth_timeout=10)
        run(client, "test \"$(uname -m)\" = aarch64 && test -f /opt/steamvr/steamxr_linuxarm64.json")
        run(client, "if pgrep -x frame-lab.arm64 >/dev/null; then echo 'Quit Frame Lab in Steam before deploying.'; exit 1; fi")
        remote_home = run(client, "printf '%s' \"$HOME\"").strip()
        directory = remote_home + "/devkit-game/Frame_Lab"
        run(client, "mkdir -p " + shlex.quote(directory))
        with client.open_sftp() as sftp:
            for path in files:
                target = directory + "/" + path.name
                sftp.put(str(path), target + ".part")
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                uploaded = run(client, "sha256sum " + shlex.quote(target + ".part")).split()[0]
                if uploaded != digest:
                    raise RuntimeError(f"Upload checksum mismatch: {path.name}")
                sftp.chmod(target + ".part", 0o755 if path.suffix in (".arm64", ".sh") else 0o644)
                sftp.posix_rename(target + ".part", target)
                print(f"Uploaded and verified: {path.name}", flush=True)
        parameters = {
            "gameid": "Frame_Lab",
            "directory": directory,
            "argv": ["./launch.sh"],
            "env": {},
            "settings": {"compat_tool": "SteamLinuxRuntime_4-arm64", "steam_play": "0"},
        }
        helper = remote_home + "/devkit-utils/steam-client-create-shortcut"
        result = run(client, "python3 " + shlex.quote(helper) + " --parms " + shlex.quote(json.dumps(parameters)))
        registration = json.loads(result)
        if "error" in registration or "success" not in registration:
            raise RuntimeError(f"Steam registration failed: {registration}")
        print("Registered Frame Lab in the Steam non-Steam library.")
        if args.launch:
            run(client, "python3 ~/devkit-utils/steam-devkit-rpc run-game gameid=Frame_Lab")
            print("Launch requested through Steam. Check ~/.local/state/frame-lab/godot.log on Frame.")


if __name__ == "__main__":
    main()
