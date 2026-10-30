# Native controller editor

While a game is running in landscape, open **Controllers → Controller Editor / Presets**. Editing is explicit and sends no gameplay touches. Tap a control to select it, drag to move it, and drag the yellow handle to resize. Scroll the top toolbar horizontally on smaller phones.

**Add** provides Wii Remote, Nunchuk, Classic and GameCube mappings, D-pads, analog sticks, a wheel steering stick, and empty gesture targets. Mappings require the corresponding emulated controller/extension to be configured in Dolphin. The editor does not change the emulated hardware extension.

**Properties** changes the selected control's name, mapping, opacity and haptics, or removes it. **Gestures** configures source → target rules: hold plus secondary input, replacement, lock, deliberate reverse unlock, shake pulse or release tap. Hold activation is automatic. Gesture actions have separate haptic settings.

**Motion** adjusts Mario Kart steering sensitivity, inversion, physical shake and recentering. In a Mario Kart preset, **Wheel / Stick** edits the two arrangements separately; the on-screen mode control switches instantly during play and releases held inputs. Protected defaults retain their original rendering and dimensions. Editable Mario Kart copies include the original button frames plus a new Shake control, 2 → Shake, and B → Up rules.

**Save & Play** saves the current preset and exits editing. **Cancel** returns to the previous arrangement. **Presets** creates an empty preset or a copy of the current protected default, imports JSON from Files, and lists saved presets. Select a saved preset to load, edit, rename, duplicate, export through the share sheet, or delete it. **Protected default — Play** resets the active layout without deleting saved user presets. The existing controller menu still selects SMB and Mario Kart defaults.

Presets are versioned JSON in Application Support/ControllerPresets, independent of the app bundle, so normal app updates preserve them. Presets are associated with the running game's ID. Reinstalling/deleting the app can remove its data; use Export to keep a separate copy. Imports are validated and always receive a new ID. Unknown future schema versions are rejected without rewriting the source file.

## Validation

The portable tests exercise JSON round trips, future-version rejection, geometry and mapping preservation, game association, import identity, ownership-based simultaneous input, drift throwing, slide locking, deliberate reverse unlock, shake pulse expiry, cancellation and mode/exit neutralization. These run before the existing unsigned IPA archive.

Physical iPhone validation is still required for steering sign in both landscape orientations, quaternion recentering and recovery, physical shake thresholds, haptic timing, game-specific D-pad interpretation, simultaneous gas/drift/item touches, interruption behavior, resize ergonomics and device-size preview accuracy. The existing Mario Kart D-pad and SMB joystick disagree on sideways rotation; custom layouts capture each convention explicitly without changing the SMB default. An IPA build alone does not prove gameplay behavior.

## Configuration switching and management

Saved sideways configurations appear directly beside Mario Kart and Super Mario Bros in the in-game Sideways Controller Layout menu. Tap a saved name to switch immediately; its native layout and motion mode are restored with it. Add Configuration creates a named copy or an empty layout. Manage Configurations provides rename, duplicate, export and delete. In the editor, New Config and Delete Config are explicit toolbar actions, and saved rows can be swiped to delete. The built-in defaults remain protected. Other controller types have a matching Controller Configurations menu.

Properties and Gestures open a control picker if no control is selected. The status line names the selected control. Empty configurations offer Add Control instead of silently ignoring the action. Existing JSON files stay in Application Support/ControllerPresets, and all compatible configurations remain available when switching native layouts or games. Configurations belonging to the running game are shown first. Saving updates the in-game list without restarting.
