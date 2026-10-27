# Azad's Steam Frame Experiments

Small VR experiments for the Valve Steam Frame, made with Godot 4.7.2 and running natively on the headset (Linux ARM64, OpenXR). There are two levels: **Eye tracking cubes**, where you select with your gaze and run a calibration, and **Cube lab**, with throwable cubes, spatial-audio spheres and a light switch.

<img width="2088" height="1557" alt="Screenshot 2026-10-27 085757" src="https://github.com/user-attachments/assets/4260395d-8add-4aed-9f81-2fb7c1733061" />


## Try it

1. On the Steam Frame, switch to **Desktop Mode** and download the latest `azads-steam-frame-experiments-…-linux-arm64.tar.gz` from [Releases](https://github.com/azadbal/SteamFrame-Godot-Azad-Experiments/releases).
2. Extract it (Dolphin: right-click → **Extract** → **Extract here**).
3. Double-click **`install.py`** in the extracted folder and choose **Execute**. A message confirms the install.
4. Back in the headset, open the Steam library → **Non-Steam** → **Azads_Steam_Frame_Experiments**.

You can delete the downloaded folder afterwards. To update, install a newer release the same way. To uninstall, run `python3 install.py --uninstall` in the extracted folder.

If the installer says Steam did not answer, turn on **Developer Mode** in Steam settings and run it again. The installer has only been tested on a Frame with Developer Mode on.

### Controls

- **Hub:** touch a level with a controller and pull that controller's trigger.
- **Options panel** (to your right in every level): press a button the same way. To move the panel, touch its frame, squeeze the grip and carry it. **Passthrough** toggles the camera view. **Return to hub** leaves the level; in the hub this button is **Quit app**.
- **Eye tracking cubes:** look at a cube and it turns orange, then green. **Calibrate** shows 9 targets: look at each and press the right trigger. The measured offset is then applied to your gaze. Any face button toggles the eye dot.
- **Cube lab:** grab (trigger) the sound spheres and place them around you to hear spatial audio. Grab and throw the cubes; they return to the table when they hit the floor. Press the switch to change the light.
- Hold the system button to recentre. Content follows the direction you faced at launch.

## How the repo works

```
levels/            hub, eye tracking level, shared XR code (main scene: levels/hub.tscn)
  hub.gd             level picker; panel shows runtime info and render resolution
  base.gd            shared rig for hub + eye tracking: XR origin, controllers, panel, passthrough, input
  tool_panel.gd      options/info panel: formatted text, buttons, grabbing, per-level default pose
  xr_support.gd      launch-direction "home" frame, controller collider queries, passthrough, controller models
  controller_collider.gd   sphere collider at each controller's tip (physics layers 20/21)
  eye_tracking_cubes.gd    gaze selection + 9-point calibration
  eye_tracking_source.gd   reads XR_EXT_eye_gaze_interaction, applies the calibration offset
  eye_tracking_math.gd     angle, bias and jitter math (unit tested)
  cube_lab.tscn      the cube lab scene; its logic is in scripts/
scripts/           cube lab: lab.gd (scene + panel), interactions.gd (grab/switch), grabbable.gd (throw/reset), sound_pulse.gdshader
tests/             self_test.gd (cube lab behaviour), smoke_levels.gd (loads levels, math and panel tests)
tools/             build.ps1, deploy.py, launch.sh, install.py, package_release.py, setup_godot.py, action-map tools
openxr_action_map.tres   controller bindings (Frame controller + Touch fallback), eye_pose and face_button actions
```

**Levels.** The hub and eye tracking level extend `levels/base.gd`, which builds the XR rig, the options panel (with **Passthrough** and **Return to hub**) and the trigger and face-button input. A level overrides `build()`, `on_frame()`, `on_trigger()`, `on_button()` and `on_recentered()`, and adds its own panel buttons with `panel.add_button()`. The cube lab predates this. It is its own scene, but it uses the same panel, collider and passthrough helpers.

**Placement.** The direction you face when the app starts becomes the "home" frame (stored with `Engine.set_meta`), and every level places content relative to it. A system-button recentre captures it again. The panel's default poses were set in the headset and live in `DEFAULT_POSES` in `tool_panel.gd`.

**Panel text.** The text is a `RichTextLabel` drawn into a 640×356 `SubViewport`, about 1.5× the display density at the panel's distance. That viewport is shown as an OpenXR quad composition layer, which the compositor samples at display resolution, with a hole punch so controllers can pass in front of it. `set_info()` takes lines starting with `# ` for headers, `- ` for bullets and `~ ` for muted notes.

**Controllers.** The runtime draws the controller models (`XR_EXT_render_model`). Touching and grabbing use a 4.5 cm sphere at the controller tip, checked with physics shape queries (`XRSupport.hand_touches_box` / `hand_touches_shape`).

**Eye tracking.** This uses `XR_EXT_eye_gaze_interaction` through an `eye_pose` action. Calibration measures the mean yaw/pitch offset over 9 targets, in head-local terms, and removes it from the gaze. Data goes to `user://eye_calibration.json` and `user://eye_tracking_accuracy.json`. Each calibration overwrites both files, and **Clear calibration** deletes them.

**Passthrough.** This is the runtime's `ALPHA_BLEND` blend mode. Levels clear to alpha 0 and hide their floor while it is on. The mode lives on the OpenXR interface, so it persists across levels.

**What the Frame's runtime supports.** SteamVR/OpenXR 2.18.2 was checked on 16 October 2026 with `--verbose`. It offers eye gaze, hand tracking, foveation, render models and the `OPAQUE` and `ALPHA_BLEND` blend modes. It offers no spatial-entity extensions, so there are no anchors, plane tracking or marker tracking. Apps get no camera frames either; passthrough is composited by the system.

**Project settings** (`[frame_lab]` in `project.godot`):

| Setting | Default | Effect |
|---|---|---|
| `debug/text_composition_layer` | on | Panel text as an OpenXR layer. When off, it is drawn as an in-scene quad; the layer can trail the scene slightly in fast head turns. |
| `debug/show_controller_colliders` | off | Draws the controller tip spheres. |
| `debug/panel_position_save` | off | Adds a **Save position** button that stores the panel pose to `user://panel_positions.json` and uses saved poses. |

**Names.** The app is called "Azad's Steam Frame Experiments" (`config/name`). That name is also the OpenXR application name and the `user://` folder, `~/.local/share/godot/app_userdata/Azad's Steam Frame Experiments/`. Keep it free of slashes, because SteamVR uses it in controller-binding paths. Build files (`frame-lab.arm64` and `.pck`), the dev devkit entry (`Frame_Lab`) and the log folder (`~/.local/state/frame-lab/`) keep the old name, Frame Lab.

## Develop

**Requirements:** Godot 4.7.2 with Linux ARM64 export templates. `python tools/setup_godot.py` installs pinned, hash-verified copies under the user profile. Deployment also needs a Steam Frame reachable over SSH.

**Edit and test on Windows:**

```powershell
.\tools\build.ps1                      # import, cube lab self-test, export build/frame-lab.arm64 + .pck
& "$env:USERPROFILE\Documents\_apps\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --xr-mode off --path . --script res://tests/smoke_levels.gd
& "$env:USERPROFILE\Documents\_apps\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --path . --xr-mode off -- --desktop   # mouse preview of the cube lab
```

**Deploy to the headset (dev entry `Frame_Lab`):** run `python tools\deploy.py --launch`. It uploads with hash checks to `~/devkit-game/Frame_Lab`, registers the build with Steam using the `SteamLinuxRuntime_4-arm64` compatibility tool, and launches it. The script asks for the SSH password or reads `FRAME_SSH_PASSWORD`. Quit the running instance first. Logs go to `~/.local/state/frame-lab/godot.log`. `vrpreferences.json` asks SteamVR for at least 90 Hz.

**Release:** run `python tools\package_release.py v0.1.1` after `build.ps1`. It writes `build/azads-steam-frame-experiments-v0.1.1-linux-arm64.tar.gz`, which keeps Unix permissions, with `install.py`, the build, `launch.sh` and `INSTALL.txt`. Attach that file to a GitHub release. `install.py` is self-contained: it copies the app to `~/devkit-game/Azads_Steam_Frame_Experiments` and registers it through `~/.steam/steam.pipe`, the same protocol Valve's devkit tools use. It doesn't need the PC devkit client.

**Develop on the Frame and sync with Windows:** both checkouts track `main` of [SteamFrame-Godot-Azad-Experiments](https://github.com/azadbal/SteamFrame-Godot-Azad-Experiments), formerly `Godot-Sf-1`; the old URL redirects.

- **Windows:** `C:\Dev\VR\Steam_frame\godot-openxr-demo`
- **Frame:** `/home/steamos/Desktop/Dev/Godot-Sf-1`. Open **Desktop → Dev → godot → Frame Lab.desktop** to start the native editor with the Frame's OpenXR runtime, press **F5**, then use Steam's **Resume Game**. The Frame pushes with its own repository-only deploy key, `/home/steamos/.ssh/godot_sf_1_ed25519`.

Run `git pull --ff-only` before editing on either device. Commit and push when done, and don't edit the same files on both at once.

**Action map:** `tools/add_eye_gaze_action.gd` and `tools/add_face_button_action.gd` add actions to `openxr_action_map.tres` and can safely be re-run. Run them with `Godot --headless --xr-mode off --path . --script res://tools/<name>.gd`.

References: [Valve's Steam Frame Godot guide](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot), [Godot XR docs](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html). No third-party assets or XR plugins are used.
