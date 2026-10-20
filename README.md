# Azad's Steam Frame Experiments

Formerly **Frame Lab**. The app name (`config/name`, also the OpenXR application name and the `user://` folder) is "Azad's Steam Frame Experiments"; build files (`frame-lab.arm64`/`.pck`), the devkit entry (`Frame_Lab`) and the log folder (`~/.local/state/frame-lab`) keep the old name.

Minimal Godot 4.7.2 OpenXR demo, built and tested natively on Steam Frame (Linux ARM64).

## Play

On the headset, open **Steam → Library → Non-Steam → Frame Lab** (the devkit entry may display `Frame_Lab`). It starts in the **hub**: touch a level (Eye tracking cubes, Cube lab) with a controller and pull that controller's trigger.

Every level has an **options and info panel** to the right of the launch direction. Its poses were placed in the headset: the hub's (63° right, 0.66 m out, 17 cm below eye height) is used in the hub and eye tracking level, and the cube lab has its own (68°, 0.73 m, 11 cm). They live in `DEFAULT_POSES` in `levels/tool_panel.gd`. Its text has a title, section headers and bullets (a `RichTextLabel` rendered into a 640x356 `SubViewport`, about 1.5x the display density at the panel's distance). Sizing it to the display (rather than a much larger texture that gets minified without mipmaps) is what removes most of the aliasing. With project setting `frame_lab/debug/text_composition_layer` on (the default), the text is an OpenXR quad composition layer with a hole punch, so SteamVR's compositor samples it at display resolution. It can trail the scene slightly during fast head turns; turn the setting off to draw the text as an in-scene quad instead. Level options sit bottom-left; **Return to hub** (in the hub, **Quit app**) sits bottom-right with **Passthrough** above it. The hub's panel lists the runtime, eye gaze and foveation support, blend modes, refresh rate and per-eye render resolution. Press a panel button the same way. To move the panel, touch it off the buttons (its frame lights up), squeeze the grip and carry it. Passthrough stays as set when you change level.

The forward direction is captured once at launch and kept for every level. Recentre with the headset's system button to capture it again. Each controller's collider is a 4.5 cm sphere around its front tip, 7 cm along the grip pose's −Z (`levels/controller_collider.gd`). Buttons, the panel, the switch and grabbing all use physics overlap queries against it. Grabbing needs the sphere within 2 cm of an object's surface. The sphere is drawn translucent while `frame_lab/debug/show_controller_colliders=true` (currently off). Earlier versions used a capsule and then convex hulls from the controller render model; rescanning the model caused stutter. Controllers are drawn with the runtime's own models (`XR_EXT_render_model`).

**Cube lab** level (the instructions and the light state are on the options panel):

- Hold the index-finger trigger **or** side grip near a cube to pick it up. Release to throw.
- Floating spheres emit different positional tones (shown by pulsing rings) and stay where released.
- Press the cyan/amber switch with a controller to change the lighting; its cap sinks while pressed. Move both hands away before pressing again.
- Open Steam's dashboard to pause interaction; quit through Steam. Focus loss releases held objects safely and pauses sounds.
- Thrown cubes return to the table when they land on the floor, fall below it, or travel more than three metres from their starting position.

This is a stationary room-scale scene using tracked controllers; it does not require optical hand tracking.

## Edit

Installed editor: `C:\Users\Azad\Documents\_apps\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe`. A **Godot 4.7.2** Start Menu shortcut is installed.

Import/open `C:\Dev\VR\Steam_frame\godot-openxr-demo\project.godot` in Godot. The main scene is `levels/hub.tscn`; every level lives in `levels/`. `levels/cube_lab.tscn` contains the cube lab's XR rig and principal scene nodes; `scripts/lab.gd` constructs the tabletop scene and audio. `scripts/interactions.gd` handles grabs and the switch; `scripts/grabbable.gd` handles throwing and floating objects. The app uses Godot's default OpenXR action map, matching the working XR template. Keep `config/name` free of slashes because SteamVR uses it in generated controller-binding paths.

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

## Hub and levels

`levels/hub.tscn` is the main scene. Its panel shows what the runtime supports (also saved to `user://capability_report.txt`). Any level can also be run directly with **F6** in the editor. Shared pieces: `levels/base.gd` (rig, panel, passthrough floor), `levels/tool_panel.gd` (the options panel), `levels/xr_support.gd` (home direction, controller probe, passthrough, controller models).

| Level | What it does |
|---|---|
| `cube_lab` | Throwable cubes, floating sound spheres and the light switch (`scripts/`). |
| `eye_tracking_cubes` | Look at a cube: it turns orange, then green after 0.8 s. Options: **Calibrate**, **Eye dot** (on by default; any face button also toggles it), **Calibration ON/OFF**, **Clear calibration**. |

**Calibrate** hides the cubes and shows 9 targets at 2 m. Look at each target and press the right trigger. The mean yaw/pitch offset between gaze and targets (head-local) is then removed from the gaze used for the cubes and dot. The panel shows the mean error before and after the correction. The offset is saved to `user://eye_calibration.json` and reloaded next time; the per-target error, bias and jitter go to `user://eye_tracking_accuracy.json`. Each calibration overwrites both files, and **Clear calibration** deletes them.

Passthrough is the runtime's `ALPHA_BLEND` blend mode. With it on, levels clear to alpha 0 (`transparent_bg`) and hide their floor.

Eye tracking uses `XR_EXT_eye_gaze_interaction` (project setting `xr/openxr/extensions/eye_gaze_interaction`) and an `eye_pose` action that `tools/add_eye_gaze_action.gd` added to `openxr_action_map.tres`. `tools/add_face_button_action.gd` added the `face_button` action (Frame: right A/B/X/Y and left d-pad; Touch: A/B/X/Y).

SteamVR/OpenXR 2.18.2 on the Frame (checked 16 October 2026 with `--verbose`) offers eye gaze, hand tracking, foveation and the `OPAQUE`/`ALPHA_BLEND` blend modes, but no spatial-entity extensions. That means no anchors, plane tracking or marker tracking, so those levels were removed.

**Debug: panel position.** With project setting `frame_lab/debug/panel_position_save=true` (currently off), the options panel has a **Save position** button at the top right. It stores the panel's pose relative to the launch direction for the current level (`hub`, `eye_tracking_cubes`, `cube_lab`) in `user://panel_positions.json` and prints it as `[Panel] saved ...`. While the setting is on, a saved pose replaces the level's default. `yaw_deg` is positive to the right; `distance_m` is horizontal; `drop_m` is below eye height. On the Frame the file is `~/.local/share/godot/app_userdata/Azad's Steam Frame Experiments/panel_positions.json`.

Headless check (no headset): `Godot --headless --xr-mode off --path . --script res://tests/smoke_levels.gd`. It loads the hub and experiment levels for a few frames and unit-tests the gaze math. It cannot exercise the XR extensions.

## Build and deploy

From this project directory:

```powershell
.\tools\build.ps1
python tools\deploy.py --launch
```

Build imports the project, runs interaction regression tests, and exports `build/frame-lab.arm64` plus `build/frame-lab.pck`. Quit the previous headset instance before deploying. Deployment prompts for the SSH password, or reads `FRAME_SSH_PASSWORD` from the process environment; no password is stored in the project. It reuses the workspace's existing Paramiko installation and trusted SSH host entry for `steamos@frame`.

The installer verifies uploaded hashes, installs under `~/devkit-game/Frame_Lab`, registers the existing Steam devkit helper with the installed `SteamLinuxRuntime_4-arm64`, and launches through Steam. `vrpreferences.json` suggests a 90 Hz per-app minimum refresh rate. SteamVR reads it at startup; if an app-specific override is already set, reset that app's video settings to defaults or choose 90 Hz there. Runtime log: `~/.local/state/frame-lab/godot.log`.

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
