import gleam/float
import gleam/int
import gleam/list
import gleeunit
import gleeunit/should
import maccel_curve/bezier
import maccel_curve/ccurve
import maccel_curve/ints
import maccel_curve/lut
import maccel_curve/point.{Point}
import maccel_curve/sysfs

pub fn main() -> Nil {
  gleeunit.main()
}

const sample_ccurve = "50.131716793596226 102.38799436733696 102.38799436733696 119.5551251568174 285.82198110514855 369.9478236665351 \r
0.09031301725212462 0.09031301725212462 0.249505317247229 0.25019168892055305 0.2502194976048541 0.2502194976048541 \r
0 0 0 0 0 0 \r
50.131716793596226 102.38799436733696 102.38799436733696 119.5551251568174 285.82198110514855 369.9478236665351 \r
0.09031301725212462 0.09031301725212462 0.249505317247229 0.25019168892055305 0.2502194976048541 0.2502194976048541 \r
0 0 0 0 0 0 \r
1.0 0.0 0 2.0 1000\r
1 0.0\r
1 0.001\r
0\r
0 0\r
1.0\r
1.0\r
"

fn near(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <. 0.000001
}

pub fn parse_ccurve_test() {
  let assert Ok(curve) = ccurve.parse(sample_ccurve)
  list.length(curve.horizontal) |> should.equal(6)
  curve.vertical |> should.equal(curve.horizontal)
  let assert [first, ..] = curve.horizontal
  let assert Ok(last) = list.last(curve.horizontal)
  near(first.x, 50.131716793596226) |> should.be_true
  near(first.y, 0.09031301725212462) |> should.be_true
  near(last.x, 369.9478236665351) |> should.be_true
}

pub fn parse_rejects_short_files_test() {
  ccurve.parse("1 2\n3 4\n") |> should.be_error
}

pub fn upto_is_inclusive_test() {
  ints.upto(3) |> should.equal([0, 1, 2, 3])
  ints.upto(0) |> should.equal([0])
  ints.upto(-1) |> should.equal([])
}

pub fn bezier_segments_test() {
  let p = fn(i) { Point(i, 0.0) }
  bezier.segments([p(0.0), p(1.0), p(2.0), p(3.0), p(4.0), p(5.0)])
  |> should.equal([
    [p(0.0), p(1.0), p(2.0), p(3.0)],
    [p(3.0), p(4.0), p(5.0)],
  ])
  bezier.segments([p(0.0)]) |> should.equal([])
}

pub fn bezier_hits_end_points_test() {
  let controls = [
    Point(0.0, 0.0),
    Point(1.0, 2.0),
    Point(3.0, 2.0),
    Point(4.0, 0.0),
  ]
  bezier.at(controls, 0.0) |> should.equal(Point(0.0, 0.0))
  bezier.at(controls, 1.0) |> should.equal(Point(4.0, 0.0))
  let mid = bezier.at(controls, 0.5)
  near(mid.x, 2.0) |> should.be_true
  near(mid.y, 1.5) |> should.be_true
}

pub fn table_is_strictly_increasing_and_anchored_test() {
  let table =
    lut.from_samples([
      Point(10.0, 1.0),
      Point(5.0, 0.5),
      Point(10.0, 1.5),
      Point(-1.0, 9.0),
      Point(20.0, 2.0),
    ])
  lut.points(table)
  |> should.equal([
    Point(0.0, 0.5),
    Point(5.0, 0.5),
    Point(10.0, 1.0),
    Point(20.0, 2.0),
  ])
}

pub fn table_is_thinned_to_the_driver_limit_test() {
  let table =
    ints.upto(999)
    |> list.map(fn(i) { Point(int.to_float(i), 1.0) })
    |> lut.from_samples
  { lut.size(table) <= lut.max_points } |> should.be_true
  let assert Ok(last) = list.last(lut.points(table))
  last.x |> should.equal(999.0)
}

pub fn eval_matches_driver_semantics_test() {
  let table =
    lut.from_pairs([0.0, 50.0, 100.0, 120.0, 400.0], [
      0.09, 0.09, 0.17, 0.25, 0.25,
    ])
  near(lut.eval(table, -5.0), 0.09) |> should.be_true
  near(lut.eval(table, 25.0), 0.09) |> should.be_true
  near(lut.eval(table, 75.0), 0.13) |> should.be_true
  near(lut.eval(table, 105.0), 0.19) |> should.be_true
  near(lut.eval(table, 120.0), 0.25) |> should.be_true
  near(lut.eval(table, 5000.0), 0.25) |> should.be_true
}

pub fn fixed_point_round_trip_test() {
  lut.to_fixed(1.0) |> should.equal(4_294_967_296)
  lut.to_fixed(0.25) |> should.equal(1_073_741_824)
  near(lut.from_fixed(lut.to_fixed(0.09031301725212462)), 0.09031301725212462)
  |> should.be_true
}

pub fn parameters_are_comma_separated_fixed_ints_test() {
  let table = lut.from_pairs([0.0, 100.0], [0.5, 1.0])
  lut.x_param(table) |> should.equal("0,429496729600")
  lut.y_param(table) |> should.equal("2147483648,4294967296")
  let assert Ok(xs) = lut.parse_param("0,429496729600\n")
  xs |> should.equal([0.0, 100.0])
  sysfs.parameters_for(table)
  |> list.map(fn(p) { p.name })
  |> should.equal(["LUT_X", "LUT_Y", "MODE"])
}

pub fn imported_curve_has_the_expected_landmarks_test() {
  let assert Ok(curve) = ccurve.parse(sample_ccurve)
  let table = curve.horizontal |> bezier.sample(64) |> lut.from_samples
  // flat floor below the first control point
  near(lut.eval(table, 0.0), 0.09031301725212462) |> should.be_true
  near(lut.eval(table, 30.0), 0.09031301725212462) |> should.be_true
  // rising through the middle of the S
  let mid = lut.eval(table, 100.0)
  { mid >. 0.12 && mid <. 0.22 } |> should.be_true
  // the near-flat ceiling: the tail rises from 0.25019 to 0.25022
  { float.absolute_value(lut.eval(table, 200.0) -. 0.2502) <. 0.0001 }
  |> should.be_true
  near(lut.eval(table, 1000.0), 0.2502194976048541) |> should.be_true
  // never decreasing
  lut.points(table)
  |> list.map(fn(p) { p.y })
  |> list.window_by_2
  |> list.all(fn(pair) { pair.1 >=. pair.0 -. 0.000001 })
  |> should.be_true
}
