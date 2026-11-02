//// JSON shapes shared by the server and the browser editor.

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{None, Some}
import maccel_curve/lut.{type Table}
import maccel_curve/point.{type Point, Point}

/// What the server reports about the driver and the saved curve.
pub type State {
  State(
    mode: Int,
    table: List(Point),
    controls: List(Point),
    warnings: List(String),
    error: Result(String, Nil),
  )
}

pub fn encode_point(p: Point) -> Json {
  json.object([#("x", json.float(p.x)), #("y", json.float(p.y))])
}

pub fn encode_points(points: List(Point)) -> Json {
  json.array(points, encode_point)
}

pub fn encode_table(table: Table) -> Json {
  encode_points(lut.points(table))
}

pub fn encode_state(state: State) -> Json {
  json.object([
    #("mode", json.int(state.mode)),
    #("table", encode_points(state.table)),
    #("controls", encode_points(state.controls)),
    #("warnings", json.array(state.warnings, json.string)),
    #("error", case state.error {
      Ok(message) -> json.string(message)
      Error(Nil) -> json.null()
    }),
  ])
}

/// JSON numbers may arrive as integers (e.g. `0`); accept both.
pub fn number() -> Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

pub fn point_decoder() -> Decoder(Point) {
  use x <- decode.field("x", number())
  use y <- decode.field("y", number())
  decode.success(Point(x:, y:))
}

pub fn points_decoder() -> Decoder(List(Point)) {
  decode.list(point_decoder())
}

pub fn state_decoder() -> Decoder(State) {
  use mode <- decode.field("mode", decode.int)
  use table <- decode.field("table", points_decoder())
  use controls <- decode.field("controls", points_decoder())
  use warnings <- decode.field("warnings", decode.list(decode.string))
  use error <- decode.field("error", decode.optional(decode.string))
  decode.success(State(
    mode:,
    table:,
    controls:,
    warnings:,
    error: case error {
      Some(message) -> Ok(message)
      None -> Error(Nil)
    },
  ))
}

/// The body the editor sends to apply a curve: its control polygon.
pub fn controls_decoder() -> Decoder(List(Point)) {
  decode.field("controls", points_decoder(), decode.success)
}

pub fn encode_controls(controls: List(Point)) -> Json {
  json.object([#("controls", encode_points(controls))])
}
