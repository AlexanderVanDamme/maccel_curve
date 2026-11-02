# maccel_curve

Bring a [Custom Curve](https://mouseacceleration.com/) `.ccurve` profile to
Linux through the [maccel](https://github.com/Gnarus-G/maccel) kernel driver
with look-up-table (LUT) support (branch `feature/lut-mode` in `~/maccel`).

The driver gets up to 128 `(speed, sensitivity)` points and interpolates
linearly between them, holding the ends flat. This tool turns the Bézier
control polygon stored in a `.ccurve` file into those points.

## Usage

```sh
# see the table and write a plot, without touching the driver
gleam run -- import best_curve_ever.ccurve --svg curve.svg

# write the table to the driver, switch it to lut mode, persist for reboots
gleam run -- import best_curve_ever.ccurve --apply

# what the driver currently holds
gleam run -- show --svg current.svg
```

Writing needs the module loaded and your user in the `maccel` group (the
udev rule makes the parameters group-writable).

Units: the Custom Curve x axis is "dots per update", which at 1000 Hz polling
is counts per millisecond, exactly what maccel feeds its curve when
`INPUT_DPI` is left at 1000. Keep `SENS_MULT` and `YX_RATIO` at 1 so the
absolute multipliers in the table apply unchanged.

## File format assumptions

The `.ccurve` format is undocumented. Rows 1-3 are read as the x, y and
weight of the horizontal curve control points, rows 4-6 as the vertical
curve. The control points are evaluated as a chain of cubic Bézier segments
(a trailing 3 or 2 points form a quadratic or linear segment), which matches
the dashed handle lines the editor draws. Weights are ignored (they are all
0 in the profiles seen so far).

## Layout

- `src/maccel_curve/ccurve.gleam`: file parser
- `src/maccel_curve/bezier.gleam`: de Casteljau evaluation and sampling
- `src/maccel_curve/lut.gleam`: table building, simplification, fixed-point
  encoding, and an `eval` mirroring the kernel interpolation
- `src/maccel_curve/sysfs.gleam`: writing/reading the module parameters and
  the reboot reset scripts
- `src/maccel_curve/plot.gleam`: SVG plot

## Browser editor (Lustre)

The editor lives in `editor/` (Gleam on the JavaScript target, Lustre 5) and
shares the curve maths in `core/` with the CLI. Build it once, then serve:

```sh
cd editor && gleam run --target erlang -m lustre/dev build --minify && cd ..
gleam run -- serve            # http://127.0.0.1:8765
```

Drag handles (their speed stays between the neighbouring handles, which keeps
the curve a proper function of speed), edit a selected point numerically, add
or delete points, and press "Apply to driver". Applying goes through the same
code path as `import --apply`: sample, simplify to 128 points, write the
module parameters, save reset scripts for reboot, and remember the control
points in `~/.config/maccel_curve/controls.json` so the editor reopens with
the handles of the curve that is currently active. The dotted green line is
what the driver currently holds.

Layout additions:

- `core/`: `point`, `bezier`, `lut`, `ints`, `format`, `curve_json`
  (shared, both targets)
- `src/maccel_curve/server.gleam`: wisp/mist server, `GET|PUT /api/state`
- `src/maccel_curve/store.gleam`: saved control polygon
- `editor/src/maccel_curve_editor.gleam`: the Lustre app

### Live speed

The speed is pushed by the server over Server-Sent Events (GET /api/speed-stream, ~100 samples/s); the editor coalesces samples to one redraw per animation frame.

The driver echoes the last input speed on every read of `/dev/maccel`
(readable by the `maccel` group). The server exposes it as `GET /api/speed`
and the editor polls it 20 times a second: a yellow marker rides the curve at
the current speed, an orange dashed line shows the peak of the last two
seconds. The driver only updates the value while the mouse moves, so after a
few unchanged readings the marker is hidden and the readout says idle.

The layout fills the window (the graph keeps a 1000:680 aspect ratio so mouse
coordinates map exactly); the Fullscreen button toggles browser fullscreen.
