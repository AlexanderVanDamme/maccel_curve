//// An SVG plot of a table, optionally with the control polygon it came from,
//// laid out like the Custom Curve editor so the two can be compared by eye.

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import maccel_curve/lut.{type Table}
import maccel_curve/ints
import maccel_curve/point.{type Point, Point}

const width = 1000.0

const height = 500.0

const margin = 60.0

type Frame {
  Frame(x_max: Float, y_max: Float)
}

pub fn svg(table: Table, controls: List(Point)) -> String {
  let frame = frame_for(table, controls)
  string.concat([
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"",
    float.to_string(width),
    "\" height=\"",
    float.to_string(height),
    "\" style=\"background:#1e1e1e;font-family:sans-serif;font-size:12px\">\n",
    grid(frame),
    control_polygon(frame, controls),
    curve(frame, table),
    table_points(frame, table),
    "</svg>\n",
  ])
}

fn frame_for(table: Table, controls: List(Point)) -> Frame {
  let all = list.append(lut.points(table), controls)
  let x_max = all |> list.map(fn(p) { p.x }) |> list.fold(400.0, float.max)
  let y_max = all |> list.map(fn(p) { p.y }) |> list.fold(0.0, float.max)
  Frame(x_max: nice_ceiling(x_max *. 1.1), y_max: nice_ceiling(y_max *. 1.25))
}

fn nice_ceiling(v: Float) -> Float {
  case v <=. 0.0 {
    True -> 1.0
    False -> {
      let magnitude = float_power10(float.floor(log10(v)))
      let step = magnitude /. 2.0
      float.ceiling(v /. step) *. step
    }
  }
}

fn log10(v: Float) -> Float {
  let assert Ok(l) = float.logarithm(v)
  l /. 2.302585092994046
}

fn float_power10(exp: Float) -> Float {
  let assert Ok(p) = float.power(10.0, exp)
  p
}

fn sx(frame: Frame, x: Float) -> Float {
  margin +. x /. frame.x_max *. { width -. 2.0 *. margin }
}

fn sy(frame: Frame, y: Float) -> Float {
  height -. margin -. y /. frame.y_max *. { height -. 2.0 *. margin }
}

fn grid(frame: Frame) -> String {
  let x_step = frame.x_max /. 8.0
  let y_step = frame.y_max /. 6.0
  let verticals =
    ints.upto(8)
    |> list.map(fn(i) {
      let x = int.to_float(i) *. x_step
      line(sx(frame, x), sy(frame, 0.0), sx(frame, x), sy(frame, frame.y_max))
      <> label(sx(frame, x), height -. margin +. 18.0, fmt(x))
    })
  let horizontals =
    ints.upto(6)
    |> list.map(fn(i) {
      let y = int.to_float(i) *. y_step
      line(sx(frame, 0.0), sy(frame, y), sx(frame, frame.x_max), sy(frame, y))
      <> label(margin -. 30.0, sy(frame, y) +. 4.0, fmt(y))
    })
  string.concat(list.append(verticals, horizontals))
  <> label(width /. 2.0, height -. 12.0, "counts / ms")
  <> "<text fill=\"#aaa\" text-anchor=\"middle\" transform=\"rotate(-90 16 250)\" x=\"16\" y=\"250\">sensitivity</text>\n"
}

fn control_polygon(frame: Frame, controls: List(Point)) -> String {
  case controls {
    [] -> ""
    _ ->
      "<polyline fill=\"none\" stroke=\"#888\" stroke-dasharray=\"6 4\" points=\""
      <> coords(frame, controls)
      <> "\"/>\n"
      <> string.concat(
        list.map(controls, fn(p) {
          circle(sx(frame, p.x), sy(frame, p.y), 4.0, "#ddd")
        }),
      )
  }
}

fn curve(frame: Frame, table: Table) -> String {
  let steps = 800
  let dense =
    ints.upto(steps)
    |> list.map(fn(i) {
      let x = int.to_float(i) /. int.to_float(steps) *. frame.x_max
      Point(x, lut.eval(table, x))
    })
  "<polyline fill=\"none\" stroke=\"#4fd6e3\" stroke-width=\"2\" points=\""
  <> coords(frame, dense)
  <> "\"/>\n"
}

fn table_points(frame: Frame, table: Table) -> String {
  table
  |> lut.points
  |> list.map(fn(p) { circle(sx(frame, p.x), sy(frame, p.y), 1.5, "#4fd6e3") })
  |> string.concat
}

fn coords(frame: Frame, points: List(Point)) -> String {
  points
  |> list.map(fn(p) {
    float.to_string(sx(frame, p.x)) <> "," <> float.to_string(sy(frame, p.y))
  })
  |> string.join(" ")
}

fn line(x1: Float, y1: Float, x2: Float, y2: Float) -> String {
  "<line stroke=\"#333\" x1=\""
  <> float.to_string(x1)
  <> "\" y1=\""
  <> float.to_string(y1)
  <> "\" x2=\""
  <> float.to_string(x2)
  <> "\" y2=\""
  <> float.to_string(y2)
  <> "\"/>\n"
}

fn circle(cx: Float, cy: Float, r: Float, fill: String) -> String {
  "<circle cx=\""
  <> float.to_string(cx)
  <> "\" cy=\""
  <> float.to_string(cy)
  <> "\" r=\""
  <> float.to_string(r)
  <> "\" fill=\""
  <> fill
  <> "\"/>\n"
}

fn label(x: Float, y: Float, text: String) -> String {
  "<text fill=\"#aaa\" text-anchor=\"middle\" x=\""
  <> float.to_string(x)
  <> "\" y=\""
  <> float.to_string(y)
  <> "\">"
  <> text
  <> "</text>\n"
}

fn fmt(v: Float) -> String {
  case v == float.floor(v) {
    True -> int.to_string(float.round(v))
    False -> float.to_string(float.round(v *. 1000.0) |> int.to_float |> fn(r) { r /. 1000.0 })
  }
}
