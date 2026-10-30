# Native controller editor implementation plan

1. Keep the existing SMB nib, sizes, transforms and touch handling as the protected default. Keep the existing Mario Kart wheel/stick overlay and dimensions as protected defaults. User layouts opt into a separate renderer.
2. Add versioned Foundation-only preset models, validated JSON persistence in Application Support, input mappings and an ownership-based multitouch gesture engine. Keep TCManagerInterface as the emulator bridge.
3. Capture current layout geometry for editable copies. Add a full-screen UIKit editor with explicit edit mode, drag, resize handles, add/remove, mappings, opacity, motion, haptics and gesture rules. Provide preset CRUD and Files JSON import/share.
4. Integrate through the emulator controller menu. Release all custom inputs on cancellation, layout/mode changes, backgrounding, hiding and game exit.
5. Add portable model/engine tests and run them in custom-ipa.yml before the existing archive. Enable this workflow for the development PR, inspect actual failures and verify the uploaded IPA.

## Inspection findings

- TCSidewaysWiiPad preserves the SMB nib and builds a separate Mario Kart overlay. Keep this boundary.
- Mario Kart wheel steering uses relative Core Motion quaternion Z twist; joystick uses synthetic tilt through the same bridge. Settings include sensitivity, inversion and recentering.
- Gas locking is currently a private single-touch surface. It supports 2 -> Lock and deliberate Lock -> 2, but has no 2 -> Shake route or direct Shake control.
- B -> item Up exists only in the joystick overlay. It writes 109 directly and can race the D-pad's releases.
- Sideways joystick maps screen left to raw Up (107), whereas the Mario Kart D-pad maps screen right to raw Up. These disagree on both axes. Resolve custom layouts explicitly and retain SMB legacy behavior.
- TCDirectionalPad and TCJoystick reset only on ended, not cancelled/failed. TCButton native targets omit touchUpOutside/touchCancel outside the Mario Kart helper.
- Existing custom-ipa.yml triggers pushes only on master; a PR trigger is needed to validate development without touching master.

## Validation boundary

Compilation and portable input-state tests cannot verify phone steering direction, shake thresholds, haptics, touch ergonomics or game-specific rotation on physical hardware. These need iPhone validation before merging.
