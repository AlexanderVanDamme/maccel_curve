//// Bézier evaluation and sampling over a chain of control points.
////
//// A control polygon p0 .. pn is split into cubic segments sharing their end
//// points ([p0 p1 p2 p3], [p3 p4 p5 p6], ...). A short tail of 3 or 2
//// points becomes a quadratic or linear segment, so any polygon is usable.
//// Points are evaluated with de Casteljau's algorithm, which works for any
//// degree.

import gleam/int
import gleam/list
import maccel_curve/ints
import maccel_curve/point.{type Point, Point}

/// Split a control polygon into segments of at most 4 points, consecutive
/// segments sharing one point.
pub fn segments(points: List(Point)) -> List(List(Point)) {
  case points {
    [] | [_] -> []
    [a, b, c, d, ..rest] -> [[a, b, c, d], ..segments([d, ..rest])]
    short -> [short]
  }
}

/// The point on the Bézier curve with these controls at parameter t.
pub fn at(controls: List(Point), t: Float) -> Point {
  case controls {
    [] -> Point(0.0, 0.0)
    [p] -> p
    many ->
      many
      |> list.window_by_2
      |> list.map(fn(pair) { point.lerp(pair.0, pair.1, t) })
      |> at(t)
  }
}

/// Evaluate every segment at `steps + 1` evenly spaced parameters.
/// Consecutive segments share their joining point, which appears twice; the
/// LUT builder removes such duplicates.
pub fn sample(points: List(Point), steps: Int) -> List(Point) {
  let steps = int.max(steps, 1)
  let ts =
    ints.upto(steps)
    |> list.map(fn(i) { int.to_float(i) /. int.to_float(steps) })

  points
  |> segments
  |> list.flat_map(fn(segment) { list.map(ts, at(segment, _)) })
}
