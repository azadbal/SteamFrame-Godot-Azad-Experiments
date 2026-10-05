# Frame Lab

Minimal Godot 4.7.2 OpenXR demo, built and tested natively on Steam Frame (Linux ARM64).

## Play

On the headset, open **Steam → Library → Non-Steam → Frame Lab** (the devkit entry may display `Frame_Lab`).

- Hold the index-finger trigger **or** side grip near a cube to pick it up. Release to throw.
- Floating cubes emit different positional tones and stay where released.
- Touch the cyan/amber button with a controller to change the lighting. Move both hands away before touching again.
- Open Steam's dashboard to pause interaction; quit through Steam. Focus loss releases held objects safely and pauses sounds.
- Thrown cubes reset when they fall below the floor or travel more than three metres from their starting position.

This is a stationary room-scale scene using tracked controllers; it does not require optical hand tracking.

## Edit

Installed editor: `C:\Users\Azad\Documents\_apps\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe`. A **Godot 4.7.2** Start Menu shortcut is installed.

Import/open `C:\Dev\VR\Steam_frame\godot-openxr-demo\project.godot` in Godot. `main.tscn` contains the XR rig and principal scene nodes; `scripts/lab.gd` constructs the tabletop scene and audio. `scripts/interactions.gd` handles grabs and the switch; `scripts/grabbable.gd` handles throwing and floating objects. Controller bindings are in `openxr_action_map.tres` (Frame and Oculus Touch profiles).

For a local mouse preview, run in PowerShell:

```powershell
& "$env:USERPROFILE\Documents\_apps\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path 'C:\Dev\VR\Steam_frame\godot-openxr-demo' --xr-mode off -- --desktop
```

Drag cubes with the left mouse button; hover over the switch to touch it. Normal launch requires OpenXR and fails explicitly if no runtime is available.

## Develop on Steam Frame and sync with Windows

Both checkouts use [Godot-Sf-1](https://github.com/azadbal/Godot-Sf-1), branch `main`:

- Windows: `C:\Dev\VR\Steam_frame\godot-openxr-demo`
- Frame: `/home/steamos/Desktop/Dev/Godot-Sf-1`

On Frame, open **Desktop → Dev → godot → Frame Lab.desktop**. This launches the native Godot 4.7.2 editor with the Frame OpenXR runtime selected. Press **F5** to run; use Steam's **Resume Game** to enter the running VR scene. Stop it from Godot before running another XR project. The previously installed Steam library build is separate; source edits appear when running from this editor.

In a terminal inside either checkout, pull before editing, then save your work in Godot and publish it:

```sh
git pull --ff-only
# Edit and save in Godot.
git status
git add <files-you-changed>
git commit -m "Describe your change"
git push
```

On the other device, save/commit any local work, then `git pull --ff-only` before opening the project. Git sync is manual; avoid editing the same files on both devices at once. If a pull refuses because histories diverged, resolve the changes rather than force-pushing. Godot caches, builds, logs, and export credentials are excluded.

Frame authenticates using its own repository-only SSH deploy key, **Steam Frame Godot-Sf-1 development**, with write access. Its private key stays in `/home/steamos/.ssh/godot_sf_1_ed25519`; Windows credentials are not copied. Revoke this key under the repository's **Settings → Deploy keys** if needed.

To verify directly on Frame:

```sh
cd /home/steamos/Desktop/Dev/Godot-Sf-1
godot=/home/steamos/Desktop/Dev/godot/Godot_v4.7.2-stable_linux.arm64
"$godot" --headless --xr-mode off --editor --import
"$godot" --headless --xr-mode off -- --self-test
```

## Build and deploy

From this project directory:

```powershell
.\tools\build.ps1
python tools\deploy.py --launch
```

Build imports the project, runs interaction regression tests, and exports `build/frame-lab.arm64` plus `build/frame-lab.pck`. Quit the previous headset instance before deploying. Deployment prompts for the SSH password, or reads `FRAME_SSH_PASSWORD` from the process environment; no password is stored in the project. It reuses the workspace's existing Paramiko installation and trusted SSH host entry for `steamos@frame`.

The installer verifies uploaded hashes, installs under `~/devkit-game/Frame_Lab`, registers the existing Steam devkit helper with the installed `SteamLinuxRuntime_4-arm64`, and launches through Steam. Runtime log: `~/.local/state/frame-lab/godot.log`.

To reinstall the pinned editor/templates, run `python tools/setup_godot.py`. Downloads are verified against the official SHA-512 sums. Linux ARM64 and Windows x64 templates are installed; the configured and device-tested export is Linux ARM64. PC VR deployment has not been tested.

## Verification — 4 October 2026

- Godot 4.7.2 import and ARM64 export passed.
- Behavior tests passed on Windows and the exported ARM64 executable: ownership, throw velocities, floating placement, touch debounce, focus safety, reset, and trigger-only grab/release through `XRController3D`.
- The first version bound only side grip. A trigger-only regression failed before the fix and passed after adding trigger support; SteamVR's generated bindings confirmed both controllers received the new mappings.
- Live runtime: SteamOS 0.4.3, SteamVR/OpenXR 2.18.2, Mobile Vulkan renderer, Adreno 750. Session initialization and rendering verified. Runtime reported 72 FPS while unfocused; this is not a full performance benchmark. The runtime warns that disabled window V-Sync falls back to enabled.
- User confirmed the touch switch, positional sounds, grabbing, and throwing work in the headset.
- Local evidence: `../outputs/godot-frame-lab/`. The first headset capture shows the dashboard, not proof of the scene; final physical acceptance is the user's confirmation.

Tracked in [AZA-224](https://linear.app/azadbalabanian/issue/AZA-224/set-up-godot-openxr-sandbox-on-steam-frame).

References: [Valve's Godot guide](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot), [Godot XR setup](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html). No third-party game assets or XR plugins are required.
