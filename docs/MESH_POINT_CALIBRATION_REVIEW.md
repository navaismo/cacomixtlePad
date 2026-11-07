# Mesh point calibration review

We reviewed the current app and Marlin/Creality sources on 2026-11-07.
This is a design assessment. We have not implemented calibration or sent
commands to a printer during this review.

## Assessment

We can build a supervised point editor with physical Z adjustments requested
in 0.01 mm increments. We must verify the installed firmware and its permitted
Z travel before enabling descent. Software limits and reported coordinates do
not independently establish the physical nozzle-to-bed clearance.

We need to distinguish these operations:

| Operation | Scope | Firmware mechanism |
| --- | --- | --- |
| Edit the selected mesh point | One cell's leveling correction | `M421 I… J… Z…` for bilinear leveling |
| Calibrate the probe Z offset | Global nozzle-to-probe relationship | `M851 Z…`, with a separate calibration procedure |
| Apply babysteps | Physical fine adjustment outside reported coordinates | `M290`, subject to firmware configuration |

Marlin documents [M421](https://marlinfw.org/docs/gcode/M421.html) as a mesh
editor and [M851](https://marlinfw.org/docs/gcode/M851.html) as probe geometry.
Changing M851 does not immediately reposition the nozzle or rewrite the existing
mesh. A selected point can locate a global calibration, but that choice must
not silently change the meaning of the saved adjustment.

## What the Ender LCD actually does

In Creality's published [LCD implementation](https://github.com/CrealityOfficial/Ender-3V3-SE/blob/main/Marlin/src/lcd/dwin/e3v2/dwin.cpp#L5470),
the point editor disables leveling compensation, raises Z for travel, moves to
the chosen XY, and adjusts Z using blocking motion. Accepting the point assigns
its edited height to the selected mesh entry. Finishing editing enables leveling
and saves settings. The global Z offset uses a separate function.

This supports a point-editing workflow, but firmware-internal blocking moves
are not proof that equivalent host G-code can cross the same Z limits.
The public source is evidence of the design, not identification of the exact
binary installed on your printer.

## Gaps in our current app

- `BedLevelPage` already exposes a selected point, but selection is informational.
- `parseBedGrid` retains indices and heights from `M420 V`; it does not retain
  physical XY geometry or the leveling enable/fade state.
- The preparation form sends `M851 Z…` and restricts input to ±2 mm. That is an
  app input range, not a verified calibration envelope for your printer.
- The USB FIFO serializes commands, but we lack an exclusive calibration session
  that also prevents starting a print, homing, probing, or moving from another
  screen. A screen-local busy flag is insufficient.
- We can reuse acknowledged modes, homing tracking, position/limit parsers, and
  the existing numbered transport. We must not bypass `execute` or relax print
  restrictions to introduce calibration.

## Proposed session

1. Require a connected, idle printer and an empty travel area. Exclude printing,
   paused jobs, cancellation, and probing. Acquire a shared operation lock before
   the first command, and hold it until cleanup finishes.
2. Read a fresh mesh and capture units, modes, motor timeout, leveling state,
   probe offset, and position. Establish homing when necessary, then re-read
   relevant state because homing can change it. Hold the motors during editing.
3. Raise Z to verified clearance before any XY travel. Prefer
   [G42](https://marlinfw.org/docs/gcode/G042.html) to address a mesh column/row,
   after verifying support. Omit its `P` option so it positions the nozzle.
   Otherwise require verified mesh origin/spacing; do not infer them from bed
   size, index labels, or the probe offset.
4. Disable compensation for the direct point-editing procedure and account for
   its coordinate transformation. Approach a verified starting height slowly.
   Never descend automatically to a mesh value just because a cell was tapped.
5. Offer **Raise 0.01 mm** and **Lower 0.01 mm**. Track the requested target using
   integer hundredths and bounded absolute moves in millimeters. Allow only one
   pending adjustment, with ACK and movement completion before another press.
   Start without press-and-hold repetition. Display the requested change and
   reported position separately; a requested increment is not measured accuracy.
6. For **Apply point**, write an absolute `M421 I… J… Z…` value derived from the
   calibrated reference, including any known gauge thickness. Include both
   indices, validate bounds, and read the mesh back to confirm only that cell
   changed. Moving Z alone does not commit a correction.
7. Offer **Save to printer** explicitly. `M500` saves current firmware settings,
   not just this cell; inspect its success response and avoid EEPROM writes on
   every press. See [M500](https://marlinfw.org/docs/gcode/M500.html).
8. Raise to clearance before leaving or changing points. Restore leveling state,
   modes/feedrate, and motor timeout deliberately. Discard must leave mesh and
   global offset unchanged. After a connection loss, invalidate the session;
   do not replay movement or resume calibration automatically.

We would place this state in a shared calibration service, outside navigation
routes. Point editing would leave M851 unchanged. A global-offset wizard would
have its own reference calculation, preview, and save behavior.

## Two conditions we cannot bypass

The installed-firmware report retained in `test/pause_parking_test.dart` has
**Z minimum 0.00**. Some mesh corrections are negative. Ordinary planned moves
can be clamped at that limit, so an ACK cannot prove the requested descent
happened. We must block a lower target outside the validated envelope. We would
not automatically issue `M211 S0` or rebase coordinates to defeat the limit.
Reaching below zero needs a separately validated firmware-specific calibration
path. See [M211](https://marlinfw.org/docs/gcode/M211.html).

We would not use M290 as the default point editor. Its physical changes are
absent from current coordinates, and it can also alter the global probe offset.
Creality's published [configuration](https://github.com/CrealityOfficial/Ender-3V3-SE/blob/main/Marlin/Configuration_adv.h#L1675)
warns that babystepping does not respect endstops and leaves
`BABYSTEP_ALWAYS_AVAILABLE` disabled. Stationary operation and side effects must
be verified on the installed build; `ok` alone is insufficient. See
[M290](https://marlinfw.org/docs/gcode/M290.html).

## Validation before enabling it

We need simulated tests for the operation lock, coordinate mapping, signs,
single-step bounds, clamping, unsupported-command responses, readback, discard,
save failure, cancellation, and disconnection. Physical checks must first confirm
XY mapping and step direction well above an empty bed, then validate the
supervised approach and persistence. The near-bed procedure remains unverified.
