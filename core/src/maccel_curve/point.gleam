//// A 2D point: x is an input speed (counts/ms), y a sensitivity multiplier.

pub type Point {
  Point(x: Float, y: Float)
}

/// Linear interpolation between two points at parameter t in [0, 1].
pub fn lerp(a: Point, b: Point, t: Float) -> Point {
  Point(x: a.x +. { b.x -. a.x } *. t, y: a.y +. { b.y -. a.y } *. t)
}

/// The y value on the straight line through a and b at the given x.
/// A vertical (or reversed) segment steps to b's value.
pub fn y_on_segment(a: Point, b: Point, x: Float) -> Float {
  case b.x <=. a.x {
    True -> b.y
    False -> a.y +. { b.y -. a.y } *. { { x -. a.x } /. { b.x -. a.x } }
  }
}
