//// The look-up table as the maccel driver understands it: up to
//// `max_points` (speed, sensitivity) pairs with strictly increasing speeds,
//// linearly interpolated in between and held flat outside the range.
////
//// `eval` mirrors the kernel interpolation so plots and tests show what the
//// driver will actually do.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import maccel_curve/point.{type Point, Point}

/// The driver storage limit (LUT_MAX_POINTS in driver/accel/lut.h).
pub const max_points = 128

/// The driver fixed-point scale on 64-bit kernels: 32 fractional bits.
pub const fixed_one = 4_294_967_296

pub opaque type Table {
  Table(points: List(Point))
}

pub fn points(table: Table) -> List(Point) {
  table.points
}

pub fn size(table: Table) -> Int {
  list.length(table.points)
}

/// Build a table from arbitrary samples: sorted by speed, duplicates and
/// backwards steps removed, negative speeds dropped, extended flat down to
/// speed 0, and simplified to at most `max_points` entries.
pub fn from_samples(samples: List(Point)) -> Table {
  samples
  |> list.filter(fn(p) { p.x >=. 0.0 })
  |> list.sort(fn(a, b) { float.compare(a.x, b.x) })
  |> strictly_increasing
  |> anchor_at_zero
  |> simplify(max_points)
  |> Table
}

/// Build a table straight from (speed, sensitivity) pairs, e.g. read back
/// from the driver.
pub fn from_pairs(xs: List(Float), ys: List(Float)) -> Table {
  list.map2(xs, ys, Point) |> from_samples
}

fn strictly_increasing(points: List(Point)) -> List(Point) {
  points
  |> list.fold([], fn(kept: List(Point), p: Point) {
    case kept {
      [last, ..] if p.x <=. last.x -> kept
      _ -> [p, ..kept]
    }
  })
  |> list.reverse
}

fn anchor_at_zero(points: List(Point)) -> List(Point) {
  case points {
    [first, ..] if first.x >. 0.0 -> [Point(0.0, first.y), ..points]
    _ -> points
  }
}

/// Reduce to at most `limit` points by repeatedly removing the interior
/// point whose removal changes the interpolated curve the least (its
/// vertical distance from the line through its neighbours). Points on flat
/// or straight stretches go first; corners and knees survive.
fn simplify(points: List(Point), limit: Int) -> List(Point) {
  case list.length(points) <= limit {
    True -> points
    False ->
      points
      |> remove_at(least_significant_index(points))
      |> simplify(limit)
  }
}

/// Index (1 .. n-2) of the interior point with the smallest deviation.
fn least_significant_index(points: List(Point)) -> Int {
  points
  |> list.window(3)
  |> list.index_map(fn(triple, i) {
    case triple {
      [a, b, c] -> #(deviation(a, b, c), i + 1)
      _ -> #(0.0, i + 1)
    }
  })
  |> list.fold(#(-1.0, 1), fn(best, candidate) {
    case best.0 <. 0.0 || candidate.0 <. best.0 {
      True -> candidate
      False -> best
    }
  })
  |> fn(best) { best.1 }
}

fn deviation(a: Point, b: Point, c: Point) -> Float {
  float.absolute_value(b.y -. point.y_on_segment(a, c, b.x))
}

fn remove_at(points: List(Point), index: Int) -> List(Point) {
  points
  |> list.index_map(fn(p, i) { #(i, p) })
  |> list.filter(fn(ip) { ip.0 != index })
  |> list.map(fn(ip) { ip.1 })
}

/// The sensitivity the driver will apply at `speed`.
pub fn eval(table: Table, speed: Float) -> Float {
  case table.points {
    [] -> 1.0
    [first, ..] if speed <=. first.x -> first.y
    points -> eval_inside(points, speed)
  }
}

fn eval_inside(points: List(Point), speed: Float) -> Float {
  case points {
    [] -> 1.0
    [last] -> last.y
    [a, b, ..] if speed <. b.x -> point.y_on_segment(a, b, speed)
    [_, ..rest] -> eval_inside(rest, speed)
  }
}

/// Round a float to the driver fixed-point integer representation.
pub fn to_fixed(value: Float) -> Int {
  float.round(value *. int.to_float(fixed_one))
}

pub fn from_fixed(value: Int) -> Float {
  int.to_float(value) /. int.to_float(fixed_one)
}

/// The comma separated value for the LUT_X module parameter.
pub fn x_param(table: Table) -> String {
  param(table, fn(p) { p.x })
}

/// The comma separated value for the LUT_Y module parameter.
pub fn y_param(table: Table) -> String {
  param(table, fn(p) { p.y })
}

fn param(table: Table, axis: fn(Point) -> Float) -> String {
  table.points
  |> list.map(fn(p) { p |> axis |> to_fixed |> int.to_string })
  |> string.join(",")
}

/// Parse a comma separated module parameter value back into floats.
pub fn parse_param(value: String) -> Result(List(Float), String) {
  value
  |> string.trim
  |> string.split(",")
  |> list.filter(fn(s) { s != "" })
  |> list.try_map(fn(s) {
    case int.parse(s) {
      Ok(i) -> Ok(from_fixed(i))
      Error(_) -> Error("not a fixed-point integer: " <> s)
    }
  })
}
