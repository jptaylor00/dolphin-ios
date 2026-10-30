# Controller branch integration

Source: `fix/mario-kart-dpad-ccw` at `0d9d460c8e7530c7c0abc914c2c1ead34b5ee282` (ten commits after the original editor base). Merged as a second parent so its history is retained.

Preserved final changes from that branch:

- Mario Kart D-pad uses the corrected direct visible-direction mapping, without rotating or resizing the views. New editable copies capture this mapping; saved JSON mappings remain explicit and are not rewritten.
- Left tilt retains its negative sign; right tilt remains positive. Joystick steering retains the full -1...1 range.
- Dedicated 76x32 Shake controls in both Mario Kart modes and the standard sideways/SMB layout. Editor copies capture the actual Shake frame and its immediate 120 ms press pulse, without adding a duplicate Shake button. Native pulses use the editor's ownership mixer so they release reliably alongside physical shake and user controls.
- Mario Kart wheel-mode A/+/− retain the newer upper-left positions from the source branch and their existing dimensions.
- SMB 1/2 retain the source branch's bottom constraint of 8 points, replacing the older 40-point baseline. Their size is unchanged. This intentionally adopts the newer layout requested by the user.
- The source branch's push trigger remains supported alongside the editor PR tests and IPA build.

The visual editor, presets, configurable gestures, cancellation cleanup, shake ownership, and all original editor changes remain present. Six regression checks cover full signed steering, neutral steering and immediate/expiring Shake pulses, in addition to the prior 38 checks.

The source branch changes the D-pad mapping but leaves the native drift-to-item helper's raw input unchanged. Game-specific interpretation of those inputs, steering sign, haptics and touch placement still require physical-device verification. No emulator internals are changed.
