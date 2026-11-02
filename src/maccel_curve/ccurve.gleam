//// Parser for Custom Curve `.ccurve` profile files.
////
//// The format is not documented by the vendor. From inspecting exported
//// files, the first three rows describe the horizontal curve and the next
//// three the vertical one:
////
////   row 1: x of each control point (dots per update == counts/ms at 1000 Hz)
////   row 2: y of each control point (sensitivity multiplier)
////   row 3: per-point weight (always 0 in the files seen so far; ignored)
////   rows 4-6: the same for the vertical curve
////   remaining rows: other profile settings (ignored)
////
//// The control points are treated as a Bézier control polygon, which matches
//// the dashed handle lines the editor draws (see `bezier`).

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import maccel_curve/point.{type Point, Point}

pub type Curve {
  Curve(horizontal: List(Point), vertical: List(Point))
}

pub fn parse(text: String) -> Result(Curve, String) {
  let rows =
    text
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { line != "" })

  case rows {
    [hx, hy, _hw, vx, vy, _vw, ..] -> {
      use horizontal <- result.try(points_from_rows(hx, hy, "horizontal"))
      use vertical <- result.try(points_from_rows(vx, vy, "vertical"))
      Ok(Curve(horizontal:, vertical:))
    }
    _ ->
      Error(
        "expected at least 6 rows (x, y, weight for each axis), got "
        <> int.to_string(list.length(rows)),
      )
  }
}

fn points_from_rows(
  xs_row: String,
  ys_row: String,
  axis: String,
) -> Result(List(Point), String) {
  use xs <- result.try(numbers(xs_row))
  use ys <- result.try(numbers(ys_row))
  case list.length(xs) == list.length(ys), xs {
    _, [] -> Error("the " <> axis <> " curve has no control points")
    False, _ ->
      Error(
        "the " <> axis <> " curve has a different number of x and y values",
      )
    True, _ ->
      Ok(list.map2(xs, ys, fn(x, y) { Point(x:, y:) }))
  }
}

/// Parse a whitespace separated row of numbers. Integers are accepted too.
fn numbers(row: String) -> Result(List(Float), String) {
  row
  |> string.split(" ")
  |> list.filter(fn(s) { s != "" })
  |> list.try_map(number)
}

fn number(s: String) -> Result(Float, String) {
  case float.parse(s) {
    Ok(f) -> Ok(f)
    Error(_) ->
      int.parse(s)
      |> result.map(int.to_float)
      |> result.replace_error("not a number: " <> s)
  }
}
