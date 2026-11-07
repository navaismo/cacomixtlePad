# Printing and bed mesh changes

We implemented these changes on 2026-11-07 after the responsive UI work.
Our target remains the Ender 3 V3 SE, with the rear toward Y maximum.

## Stable thumbnails

We found that library and print progress rebuilds decoded the same Base64
thumbnail into new bytes. Each `MemoryImage` then had a different cache key,
which could clear the visible frame while Flutter decoded another copy.

We now keep the decoded image provider in `GcodeThumbnail` until its content
changes, use gapless playback, and isolate its repaint. The library and print
page share this widget. Invalid Base64 and image decoding errors retain a
fallback icon.

## Pause and return

We perform the entire sequence in `PrintJobService` through `execute` and the
existing numbered FIFO. Screens do not send parking commands.

1. We finish the pending ACK and drain accepted movements with `M400`.
2. We save the runtime motor timeout and send `M84 S0` to keep the axes held.
   We query the logical position with `M114` and enabled soft limits with `M211`.
3. We require acknowledged XYZ homing and known units, axis mode, and extrusion
   mode. We switch temporarily to millimeters and absolute axes.
4. We lift Z by 30 mm, capped at the reported Z maximum. With less than 5 mm
   available clearance, we pause in place. Otherwise, we move rearward to
   Y maximum minus 5 mm, keeping the current Y if it is already farther back.
5. We drain movement again and compare the reported position with the target.
   Only then do we enable Resume. A reduced lift has its own visible message.
6. On Resume, we recheck position and limits, return XY while elevated, lower Z,
   drain movement, and check the reported return position. We restore units,
   axis/extrusion modes, and the motor timeout before sending the next file line.

We initialize `G21`, `G90`, `M82`, and a **120-second runtime motor idle timeout**
with `M84 S120` during connection. This gives us explicit session defaults,
including when reconnecting without a firmware reset. A later acknowledged
`M18 S…` or `M84 S…` in your G-code updates the timeout we preserve. We do not
save these defaults to EEPROM. Setting an idle timeout does not invalidate
homing; commands that actually disable motors do.

Parking and return use `G0` without `E` or `F`: we leave the extruder coordinate
and modal feedrate untouched. Firmware movement speeds and axis limits apply.
We temporarily block manual Z offset changes throughout pause, return, and
cancellation. Cancel remains available during both transitions. After the pending
ACK, we turn off the hotend, bed, and fan, drain accepted moves, and recheck
homing, modes, position, enabled limits, and clearance before lifting and
parking toward the rear. If cancellation interrupts parking or return, we check
the reported position against the expected stages and finish parking without
repeating an already completed lift or returning to the print. If no file command
has been sent, cancellation does not initiate a parking move.

If preflight is unavailable or less than 5 mm of lift is possible, cancellation
finishes in place and shows a warning on Home. A limited lift also shows a
warning. A mismatch or command failure instead fails the job and remains visible;
it does not report successful cancellation. We restore command modes and the
motor timeout when possible. A new connection establishes defaults after a
disconnect.

If preflight information is unavailable, we stay paused in place with a visible
message. If a reported position differs after movement or before return, we
fail the job and cool down instead of continuing the file. We do not home or
disable soft limits to bypass these checks. Pause snapshots live only in memory;
a recovered job record remains interrupted and cannot authorize a return move.

`M114` reports logical coordinates, not an independent measurement of the head.
Do not move the head by hand or release the motors during a pause. We still
need to validate stock firmware responses, clearances, long pauses, and the
actual return path on your phone and printer. Process death cannot restore the
previous runtime timeout; reconnect or restart the printer before another job.

We also accept the installed firmware's reported `M211` bounds in
`X-13.00 Y-15.00 Z0.00` form, without colons. All other parking checks remain
in force. The reported format is covered by a simulated response; physical
parking and return still need validation.

Our choices follow Marlin's [M114 position reporting](https://marlinfw.org/docs/gcode/M114.html),
[M211 soft limits](https://marlinfw.org/docs/gcode/M211.html), and
[M18/M84 timeout behavior](https://marlinfw.org/docs/gcode/M018.html).
We checked the [G0 feedrate implementation](https://github.com/MarlinFirmware/Marlin/blob/2.1.2.5/Marlin/src/gcode/motion/G0_G1.cpp)
and [motor timeout implementation](https://github.com/MarlinFirmware/Marlin/blob/2.1.2.5/Marlin/src/gcode/control/M17_M18_M84.cpp)
in Marlin 2.1.2.5. Your installed firmware still needs physical validation.

## Bed mesh

We replaced the default canvas-only view with a selectable height map, rounded
cells, a zero-centered blue/coral legend, and separate minimum, maximum, and
range summaries. A flat mesh reports a zero range. Colors use a symmetric scale
with a minimum extent of ±0.05 mm; the displayed numbers remain the measured
values. We retain a 3D surface option with the same palette and summaries.

Y increases toward the top/rear; X and Y labels identify mesh indices, not
millimeter positions. Dense meshes and enlarged text scroll horizontally;
the page scrolls vertically. We keep the previous valid mesh when a refresh
fails, expose Retry, and disable duplicate refresh/probe requests until both
probing and the subsequent mesh read finish. We reject incomplete or nonfinite
meshes instead of filling missing measurements with zero.
The selected point and mesh summaries appear below the grid and probing controls
on the right, or below them when the page stacks on narrow displays. Selecting a
point currently only displays its value; it does not move the printer or change
the mesh.

## Validation

All 136 tests pass, static analysis is clean, and all seven languages have
111 translation keys. We rebuilt `build/app/outputs/flutter-apk/app-debug.apk`
successfully and passed `git diff --check`.

We use simulated USB transport for automated tests. The regression checks cover
thumbnail provider/frame stability, print progress rebuilds, parking and return
order, units/extrusion modes, travel clamping, unsupported reports, cancellation,
disconnection, and interrupted history. UI checks cover mesh selection, both
views, failed refresh recovery, probing states, small viewports, keyboard insets,
and enlarged German text. We also inspected rendered 4 × 4 mesh previews.

Before printing a part, validate a cold pause/return above an empty bed, then a
short supervised print. Check a normal lift, a lift near Z maximum, a pause
longer than two minutes, cancellation, and USB disconnection. These hardware
checks remain pending; automated ACKs do not establish physical movement.
