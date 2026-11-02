//// Browser editor for the maccel look-up table curve.
////
//// The curve is a Bézier control polygon (same model as the `.ccurve`
//// importer). Drag the handles, watch the sampled table the driver will get,
//// and press Apply to send it to the local maccel_curve server.

import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute.{attribute}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event
import maccel_curve/bezier
import maccel_curve/curve_json.{type State}
import maccel_curve/format
import maccel_curve/ints
import maccel_curve/lut.{type Table}
import maccel_curve/point.{type Point, Point}
import rsvp

// GEOMETRY --------------------------------------------------------------------

const width = 1000.0

const height = 680.0

const margin = 60.0

const steps = 64

// MODEL -----------------------------------------------------------------------

pub type Model {
  Model(
    controls: List(Point),
    table: Table,
    driver: Option(Table),
    driver_mode: Int,
    selected: Option(Int),
    dragging: Bool,
    x_max: Float,
    y_max: Float,
    hover: Option(Float),
    status: String,
    error: Option(String),
    busy: Bool,
    live: Live,
  )
}

/// What the driver reports about the mouse right now.
pub type Live {
  Live(speed: Float, stale: Int, history: List(Float))
}

fn default_controls() -> List(Point) {
  [Point(0.0, 1.0), Point(50.0, 1.0), Point(100.0, 1.5), Point(150.0, 1.5)]
}

fn init(_args: Nil) -> #(Model, Effect(Msg)) {
  let controls = default_controls()
  let model =
    Model(
      controls:,
      table: recompute(controls),
      driver: None,
      driver_mode: -1,
      selected: None,
      dragging: False,
      x_max: 400.0,
      y_max: 2.0,
      hover: None,
      status: "loading driver state...",
      error: None,
      busy: True,
      live: Live(speed: 0.0, stale: 0, history: []),
    )
  #(model, effect.batch([load(), listen()]))
}

fn recompute(controls: List(Point)) -> Table {
  controls |> bezier.sample(steps) |> lut.from_samples
}

fn fit_axes(model: Model) -> Model {
  let xs = list.map(model.controls, fn(p) { p.x })
  let ys = list.map(model.controls, fn(p) { p.y })
  let x_max = list.fold(xs, 100.0, float.max) *. 1.2
  let y_max = list.fold(ys, 0.1, float.max) *. 1.3
  Model(..model, x_max: nice(x_max), y_max: nice(y_max))
}

/// Round up to a "nice" number so the grid labels stay readable.
fn nice(v: Float) -> Float {
  case v <=. 0.0 {
    True -> 1.0
    False -> {
      let exponent = float.floor(log10(v))
      let step = power10(exponent) /. 2.0
      float.ceiling(v /. step) *. step
    }
  }
}

fn log10(v: Float) -> Float {
  let assert Ok(l) = float.logarithm(v)
  l /. 2.302585092994046
}

fn power10(e: Float) -> Float {
  let assert Ok(p) = float.power(10.0, e)
  p
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  ServerReturned(Result(State, rsvp.Error(String)))
  Applied(Result(State, rsvp.Error(String)))
  Pressed(Int)
  Moved(Float, Float)
  Released
  Left
  Selected(Int)
  ChangedX(String)
  ChangedY(String)
  AddedPoint
  DeletedPoint
  ChangedXMax(String)
  ChangedYMax(String)
  Apply
  Reload
  Fullscreen
  Speed(Float)
}

fn load() -> Effect(Msg) {
  rsvp.get(
    "/api/state",
    rsvp.expect_json(curve_json.state_decoder(), ServerReturned),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ServerReturned(Ok(state)) -> {
      let controls = case state.controls {
        [] -> model.controls
        saved -> saved
      }
      let model =
        Model(
          ..model,
          controls:,
          table: recompute(controls),
          driver: Some(lut.from_samples(state.table)),
          driver_mode: state.mode,
          status: describe_driver(state),
          error: option.from_result(state.error),
          busy: False,
        )
        |> fit_axes
      #(model, effect.none())
    }
    ServerReturned(Error(error)) -> #(
      Model(..model, error: Some(describe_http(error)), busy: False),
      effect.none(),
    )
    Applied(Ok(state)) -> {
      let warnings = case state.warnings {
        [] -> ""
        some -> "\n" <> string.join(some, "\n")
      }
      #(
        Model(
          ..model,
          driver: Some(lut.from_samples(state.table)),
          driver_mode: state.mode,
          status: "applied: " <> describe_driver(state) <> warnings,
          error: option.from_result(state.error),
          busy: False,
        ),
        effect.none(),
      )
    }
    Applied(Error(error)) -> #(
      Model(..model, error: Some(describe_http(error)), busy: False),
      effect.none(),
    )
    Pressed(i) -> #(
      Model(..model, selected: Some(i), dragging: True),
      effect.none(),
    )
    Moved(px, py) -> {
      let x = to_data_x(model, px)
      let y = to_data_y(model, py)
      let model = Model(..model, hover: Some(x))
      case model.dragging, model.selected {
        True, Some(i) -> #(
          set_point(model, i, Point(float.max(x, 0.0), float.max(y, 0.0))),
          effect.none(),
        )
        _, _ -> #(model, effect.none())
      }
    }
    Released -> #(Model(..model, dragging: False), effect.none())
    Left -> #(Model(..model, dragging: False, hover: None), effect.none())
    Selected(i) -> #(Model(..model, selected: Some(i)), effect.none())
    ChangedX(text) -> #(
      edit_selected(model, text, fn(p, v) { Point(..p, x: v) }),
      effect.none(),
    )
    ChangedY(text) -> #(
      edit_selected(model, text, fn(p, v) { Point(..p, y: v) }),
      effect.none(),
    )
    AddedPoint -> #(add_point(model), effect.none())
    DeletedPoint -> #(delete_point(model), effect.none())
    ChangedXMax(text) ->
      case format.parse_float(text) {
        Ok(v) if v >. 0.0 -> #(Model(..model, x_max: v), effect.none())
        _ -> #(model, effect.none())
      }
    ChangedYMax(text) ->
      case format.parse_float(text) {
        Ok(v) if v >. 0.0 -> #(Model(..model, y_max: v), effect.none())
        _ -> #(model, effect.none())
      }
    Apply -> #(
      Model(..model, busy: True, status: "applying...", error: None),
      rsvp.put(
        "/api/state",
        curve_json.encode_controls(model.controls),
        rsvp.expect_json(curve_json.state_decoder(), Applied),
      ),
    )
    Reload -> #(Model(..model, busy: True, status: "reloading..."), load())
    Fullscreen -> #(model, effect.from(fn(_) { toggle_fullscreen() }))
    Speed(speed) -> #(
      Model(..model, live: observe(model.live, speed)),
      effect.none(),
    )
  }
}

fn describe_driver(state: State) -> String {
  "driver mode "
  <> int.to_string(state.mode)
  <> case state.mode {
    4 -> " (lut), "
    -1 -> " (unavailable), "
    _ -> " (not lut: table inactive), "
  }
  <> int.to_string(list.length(state.table))
  <> " points loaded"
}

fn describe_http(error: rsvp.Error(String)) -> String {
  case error {
    rsvp.BadBody -> "the server sent an unreadable response"
    rsvp.BadUrl(url) -> "bad url: " <> url
    rsvp.HttpError(response) ->
      "server error " <> int.to_string(response.status)
    rsvp.JsonError(_) -> "the server sent invalid json"
    rsvp.NetworkError -> "cannot reach the maccel_curve server"
    rsvp.UnhandledResponse(_) -> "unexpected server response"
  }
}

fn set_point(model: Model, index: Int, p: Point) -> Model {
  let controls =
    list.index_map(model.controls, fn(existing, i) {
      case i == index {
        True -> constrain(model.controls, index, p)
        False -> existing
      }
    })
  Model(..model, controls:, table: recompute(controls))
}

fn edit_selected(
  model: Model,
  text: String,
  change: fn(Point, Float) -> Point,
) -> Model {
  case model.selected, format.parse_float(text) {
    Some(i), Ok(v) ->
      case selected_point(model) {
        Some(p) -> set_point(model, i, change(p, float.max(v, 0.0)))
        None -> model
      }
    _, _ -> model
  }
}

fn selected_point(model: Model) -> Option(Point) {
  case model.selected {
    Some(i) ->
      model.controls
      |> list.drop(i)
      |> list.first
      |> option.from_result
    None -> None
  }
}

/// Insert a point halfway to the next one (or 50 counts/ms past the end).
fn add_point(model: Model) -> Model {
  let index = option.unwrap(model.selected, list.length(model.controls) - 1)
  let before = list.take(model.controls, index + 1)
  let after = list.drop(model.controls, index + 1)
  let new = case list.last(before), list.first(after) {
    Ok(a), Ok(b) -> point.lerp(a, b, 0.5)
    Ok(a), Error(Nil) -> Point(a.x +. 50.0, a.y)
    Error(Nil), _ -> Point(0.0, 1.0)
  }
  let controls = list.flatten([before, [new], after])
  Model(
    ..model,
    controls:,
    table: recompute(controls),
    selected: Some(index + 1),
  )
}

fn delete_point(model: Model) -> Model {
  case model.selected, list.length(model.controls) > 2 {
    Some(index), True -> {
      let controls =
        model.controls
        |> list.index_map(fn(p, i) { #(i, p) })
        |> list.filter(fn(ip) { ip.0 != index })
        |> list.map(fn(ip) { ip.1 })
      Model(
        ..model,
        controls:,
        table: recompute(controls),
        selected: Some(int.max(index - 1, 0)),
      )
    }
    _, _ -> model
  }
}

// COORDINATES -----------------------------------------------------------------

fn to_screen_x(model: Model, x: Float) -> Float {
  margin +. x /. model.x_max *. { width -. 2.0 *. margin }
}

fn to_screen_y(model: Model, y: Float) -> Float {
  height -. margin -. y /. model.y_max *. { height -. 2.0 *. margin }
}

fn to_data_x(model: Model, px: Float) -> Float {
  { px -. margin } /. { width -. 2.0 *. margin } *. model.x_max
}

fn to_data_y(model: Model, py: Float) -> Float {
  { height -. margin -. py } /. { height -. 2.0 *. margin } *. model.y_max
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("app")], [
    sidebar(model),
    html.div([attribute.class("graph")], [graph(model)]),
  ])
}

fn sidebar(model: Model) -> Element(Msg) {
  html.div([attribute.class("panel")], [
    html.h1([], [element.text("maccel curve")]),
    html.div([attribute.class("status")], [element.text(model.status)]),
    case model.error {
      Some(message) ->
        html.div([attribute.class("status error")], [element.text(message)])
      None -> element.none()
    },
    html.div([attribute.class("row")], [
      html.button(
        [
          attribute.class("primary"),
          attribute.disabled(model.busy),
          event.on_click(Apply),
        ],
        [element.text("Apply to driver")],
      ),
      html.button([attribute.disabled(model.busy), event.on_click(Reload)], [
        element.text("Reload"),
      ]),
      html.button([event.on_click(Fullscreen)], [element.text("Fullscreen")]),
    ]),
    html.div([attribute.class("status")], [
      element.text(
        "table: "
        <> int.to_string(lut.size(model.table))
        <> " of "
        <> int.to_string(lut.max_points)
        <> " points",
      ),
    ]),
    hover_readout(model),
    live_readout(model),
    selected_editor(model),
    html.div([attribute.class("row")], [
      html.button([event.on_click(AddedPoint)], [element.text("Add point")]),
      html.button(
        [
          attribute.disabled(
            option.is_none(model.selected) || list.length(model.controls) <= 2,
          ),
          event.on_click(DeletedPoint),
        ],
        [element.text("Delete point")],
      ),
    ]),
    html.div([attribute.class("row")], [
      number_input("x max", model.x_max, 0, ChangedXMax),
      number_input("y max", model.y_max, 2, ChangedYMax),
    ]),
    point_list(model),
  ])
}

fn hover_readout(model: Model) -> Element(Msg) {
  case model.hover {
    Some(x) if x >=. 0.0 ->
      html.div([attribute.class("status")], [
        element.text(
          "at "
          <> format.fixed(x, 1)
          <> " counts/ms: sensitivity "
          <> format.fixed(lut.eval(model.table, x), 4),
        ),
      ])
    _ ->
      html.div([attribute.class("status")], [
        element.text("hover the graph to read the curve"),
      ])
  }
}

fn selected_editor(model: Model) -> Element(Msg) {
  case model.selected, selected_point(model) {
    Some(i), Some(p) ->
      html.div([attribute.class("row")], [
        html.span([], [element.text("point " <> int.to_string(i + 1))]),
        number_input("speed", p.x, 3, ChangedX),
        number_input("sens", p.y, 5, ChangedY),
      ])
    _, _ ->
      html.div([attribute.class("status")], [
        element.text("click a handle to edit it"),
      ])
  }
}

fn number_input(
  label: String,
  value: Float,
  decimals: Int,
  on_change: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([], [
    element.text(label),
    html.input([
      attribute.type_("number"),
      attribute.step("any"),
      attribute.value(format.short(value, decimals)),
      event.on_change(on_change),
    ]),
  ])
}

fn point_list(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("points")],
    list.index_map(model.controls, fn(p, i) {
      html.button(
        [
          attribute.class(case model.selected == Some(i) {
            True -> "selected"
            False -> ""
          }),
          event.on_click(Selected(i)),
        ],
        [
          element.text(
            int.to_string(i + 1)
            <> ".  "
            <> format.fixed(p.x, 1)
            <> "  ->  "
            <> format.fixed(p.y, 4),
          ),
        ],
      )
    }),
  )
}

fn graph(model: Model) -> Element(Msg) {
  svg.svg(
    [
      attribute("preserveAspectRatio", "xMidYMid meet"),
      attribute(
        "viewBox",
        "0 0 " <> float_attr(width) <> " " <> float_attr(height),
      ),
      attribute.class(case model.dragging {
        True -> "dragging"
        False -> ""
      }),
      event.on("mousemove", mouse(Moved)),
      event.on("mouseup", decode.success(Released)),
      event.on("mouseleave", decode.success(Left)),
    ],
    list.flatten([
      [
        svg.rect([
          attribute("x", "0"),
          attribute("y", "0"),
          attribute("width", float_attr(width)),
          attribute("height", float_attr(height)),
          attribute("fill", "#1e1e1e"),
        ]),
      ],
      grid(model),
      driver_curve(model),
      [control_polygon(model), curve(model)],
      live_marker(model),
      handles(model),
    ]),
  )
}

fn mouse(to_msg: fn(Float, Float) -> Msg) -> Decoder(Msg) {
  use x <- decode.field("offsetX", curve_json.number())
  use y <- decode.field("offsetY", curve_json.number())
  use shown_width <- decode.subfield(
    ["currentTarget", "clientWidth"],
    curve_json.number(),
  )
  // The svg keeps the viewBox aspect ratio (CSS aspect-ratio), so one
  // uniform scale maps CSS pixels back to viewBox units.
  let scale = case shown_width >. 0.0 {
    True -> shown_width /. width
    False -> 1.0
  }
  decode.success(to_msg(x /. scale, y /. scale))
}

fn grid(model: Model) -> List(Element(Msg)) {
  let verticals =
    ints.upto(8)
    |> list.flat_map(fn(i) {
      let x = int.to_float(i) *. model.x_max /. 8.0
      let sx = to_screen_x(model, x)
      [
        grid_line(
          sx,
          to_screen_y(model, 0.0),
          sx,
          to_screen_y(model, model.y_max),
        ),
        label(sx, height -. margin +. 18.0, format.short(x, 1), "middle"),
      ]
    })
  let horizontals =
    ints.upto(6)
    |> list.flat_map(fn(i) {
      let y = int.to_float(i) *. model.y_max /. 6.0
      let sy = to_screen_y(model, y)
      [
        grid_line(
          to_screen_x(model, 0.0),
          sy,
          to_screen_x(model, model.x_max),
          sy,
        ),
        label(margin -. 8.0, sy +. 4.0, format.short(y, 3), "end"),
      ]
    })
  list.flatten([
    verticals,
    horizontals,
    [
      label(width /. 2.0, height -. 12.0, "counts / ms", "middle"),
      svg.text(
        [
          attribute("x", "16"),
          attribute("y", float_attr(height /. 2.0)),
          attribute("text-anchor", "middle"),
          attribute(
            "transform",
            "rotate(-90 16 " <> float_attr(height /. 2.0) <> ")",
          ),
        ],
        "sensitivity",
      ),
    ],
  ])
}

fn grid_line(x1: Float, y1: Float, x2: Float, y2: Float) -> Element(Msg) {
  svg.line([
    attribute("x1", float_attr(x1)),
    attribute("y1", float_attr(y1)),
    attribute("x2", float_attr(x2)),
    attribute("y2", float_attr(y2)),
    attribute("stroke", "#333"),
  ])
}

fn label(x: Float, y: Float, text: String, anchor: String) -> Element(Msg) {
  svg.text(
    [
      attribute("x", float_attr(x)),
      attribute("y", float_attr(y)),
      attribute("text-anchor", anchor),
    ],
    text,
  )
}

/// What the driver currently holds, faint, for comparison.
fn driver_curve(model: Model) -> List(Element(Msg)) {
  case model.driver {
    Some(table) ->
      case lut.size(table) {
        0 -> []
        _ -> [
          svg.polyline([
            attribute("fill", "none"),
            attribute("stroke", "#8a6"),
            attribute("stroke-dasharray", "2 4"),
            attribute("points", dense_points(model, table)),
          ]),
        ]
      }
    None -> []
  }
}

fn curve(model: Model) -> Element(Msg) {
  svg.polyline([
    attribute("fill", "none"),
    attribute("stroke", "#4fd6e3"),
    attribute("stroke-width", "2"),
    attribute("points", dense_points(model, model.table)),
  ])
}

fn dense_points(model: Model, table: Table) -> String {
  ints.upto(400)
  |> list.map(fn(i) {
    let x = int.to_float(i) /. 400.0 *. model.x_max
    coord(model, Point(x, lut.eval(table, x)))
  })
  |> string.join(" ")
}

fn control_polygon(model: Model) -> Element(Msg) {
  svg.polyline([
    attribute("fill", "none"),
    attribute("stroke", "#777"),
    attribute("stroke-dasharray", "6 4"),
    attribute(
      "points",
      model.controls |> list.map(coord(model, _)) |> string.join(" "),
    ),
  ])
}

fn handles(model: Model) -> List(Element(Msg)) {
  list.index_map(model.controls, fn(p, i) {
    let selected = model.selected == Some(i)
    svg.circle([
      attribute.class("handle"),
      attribute("cx", float_attr(to_screen_x(model, p.x))),
      attribute("cy", float_attr(to_screen_y(model, p.y))),
      attribute("r", case selected {
        True -> "8"
        False -> "6"
      }),
      attribute("fill", case selected {
        True -> "#4fd6e3"
        False -> "#ddd"
      }),
      attribute("stroke", "#1e1e1e"),
      attribute("stroke-width", "2"),
      event.on_mouse_down(Pressed(i)) |> event.prevent_default,
    ])
  })
}

fn coord(model: Model, p: Point) -> String {
  float_attr(to_screen_x(model, p.x))
  <> ","
  <> float_attr(to_screen_y(model, p.y))
}

fn float_attr(v: Float) -> String {
  format.short(v, 2)
}

// MAIN ------------------------------------------------------------------------

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

/// Keep a handle between its neighbours on the speed axis. With the control
/// x values in order, the Bézier x(t) is monotonic, so the curve stays a
/// function of speed and the sampled table cannot fold back on itself.
fn constrain(controls: List(Point), index: Int, p: Point) -> Point {
  let lower = case index > 0 {
    True ->
      controls
      |> list.drop(index - 1)
      |> list.first
      |> result_map_x
    False -> 0.0
  }
  let upper =
    controls
    |> list.drop(index + 1)
    |> list.first
    |> result_map_x_or(1.0e9)
  Point(..p, x: float.min(float.max(p.x, lower), upper))
}

fn result_map_x(r: Result(Point, Nil)) -> Float {
  result_map_x_or(r, 0.0)
}

fn result_map_x_or(r: Result(Point, Nil), fallback: Float) -> Float {
  case r {
    Ok(p) -> p.x
    Error(Nil) -> fallback
  }
}

// LIVE SPEED ------------------------------------------------------------------

/// After stale_after unchanged frames the mouse is taken as idle: the driver
/// only updates the value while the mouse moves.
const stale_after = 10

const history_length = 40

fn observe(live: Live, speed: Float) -> Live {
  let stale = case speed == live.speed {
    True -> live.stale + 1
    False -> 0
  }
  Live(
    speed:,
    stale:,
    history: [speed, ..list.take(live.history, history_length - 1)],
  )
}

fn is_moving(live: Live) -> Bool {
  live.stale < stale_after && live.speed >. 0.0
}

fn peak(live: Live) -> Float {
  list.fold(live.history, 0.0, float.max)
}

fn live_readout(model: Model) -> Element(Msg) {
  let live = model.live
  html.div([attribute.class("status live")], [
    element.text(case is_moving(live) {
      True ->
        "mouse now: "
        <> format.fixed(live.speed, 1)
        <> " counts/ms, sensitivity "
        <> format.fixed(lut.eval(model.table, live.speed), 4)
      False -> "mouse idle (last " <> format.fixed(live.speed, 1) <> " counts/ms)"
    }),
    html.br([]),
    element.text("peak (last 2 s): " <> format.fixed(peak(live), 1) <> " counts/ms"),
  ])
}

fn live_marker(model: Model) -> List(Element(Msg)) {
  let live = model.live
  let peak_line = case peak(live) >. 0.0 {
    True -> [
      svg.line([
        attribute("x1", float_attr(to_screen_x(model, peak(live)))),
        attribute("y1", float_attr(to_screen_y(model, 0.0))),
        attribute("x2", float_attr(to_screen_x(model, peak(live)))),
        attribute("y2", float_attr(to_screen_y(model, model.y_max))),
        attribute("stroke", "#a85"),
        attribute("stroke-dasharray", "3 5"),
      ]),
    ]
    False -> []
  }
  let now = case is_moving(live) {
    True -> {
      let x = float.min(live.speed, model.x_max)
      let sx = to_screen_x(model, x)
      let sy = to_screen_y(model, lut.eval(model.table, x))
      [
        svg.line([
          attribute("x1", float_attr(sx)),
          attribute("y1", float_attr(to_screen_y(model, 0.0))),
          attribute("x2", float_attr(sx)),
          attribute("y2", float_attr(to_screen_y(model, model.y_max))),
          attribute("stroke", "#f6c744"),
        ]),
        svg.circle([
          attribute("cx", float_attr(sx)),
          attribute("cy", float_attr(sy)),
          attribute("r", "7"),
          attribute("fill", "#f6c744"),
          attribute("stroke", "#1e1e1e"),
          attribute("stroke-width", "2"),
          attribute("pointer-events", "none"),
        ]),
        svg.text(
          [
            attribute("x", float_attr(sx +. 10.0)),
            attribute("y", float_attr(sy -. 10.0)),
            attribute("fill", "#f6c744"),
          ],
          format.fixed(live.speed, 0) <> " counts/ms",
        ),
      ]
    }
    False -> []
  }
  list.append(peak_line, now)
}

@external(javascript, "./maccel_curve_editor_ffi.mjs", "toggle_fullscreen")
fn toggle_fullscreen() -> Nil

fn listen() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    listen_speeds("/api/speed-stream", fn(speed) { dispatch(Speed(speed)) })
  })
}

@external(javascript, "./maccel_curve_editor_ffi.mjs", "listen_speeds")
fn listen_speeds(url: String, callback: fn(Float) -> Nil) -> Nil
