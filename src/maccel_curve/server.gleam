//// A small local web server: serves the Lustre editor and an API that
//// applies curves exactly like the `import` command does.
////
////   GET  /              the editor page
////   GET  /static/...    the editor's compiled JavaScript
////   GET  /api/state     driver mode, loaded table, saved control polygon
////   PUT  /api/state     {"controls": [{x, y}, ...]} -> sample, apply, save

import gleam/dynamic/decode
import gleam/http.{Get, Put}
import gleam/json
import gleam/list
import gleam/result
import maccel_curve/bezier
import maccel_curve/curve_json.{type State, State}
import maccel_curve/lut
import maccel_curve/store
import maccel_curve/sysfs
import mist
import gleam/erlang/process
import gleam/http/request.{type Request as HttpRequest}
import gleam/http/response
import gleam/otp/actor
import gleam/string_tree
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub const default_port = 8765

pub const default_steps = 64

/// Serve forever on 127.0.0.1:port; `static_dir` holds the built editor.
pub fn serve(port: Int, static_dir: String) -> Result(Nil, String) {
  use <- require_free_port(port)
  let secret = wisp.random_string(64)
  let handler = fn(req) { handle(req, static_dir) }

  let web = wisp_mist.handler(handler, secret)
  let route = fn(req: HttpRequest(mist.Connection)) {
    case request.path_segments(req) {
      ["api", "speed-stream"] -> speed_stream(req)
      _ -> web(req)
    }
  }

  mist.new(route)
  |> mist.bind("127.0.0.1")
  |> mist.port(port)
  |> mist.start
  |> result.map_error(fn(_) { "could not start the server on port " <> int_to_string(port) })
  |> result.map(fn(_) { process.sleep_forever() })
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String

fn handle(req: Request, static_dir: String) -> Response {
  case request.path_segments(req) {
    ["api", "speed"] -> speed()
    _ -> handle_logged(req, static_dir)
  }
}

fn handle_logged(req: Request, static_dir: String) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use <- wisp.serve_static(req, under: "/static", from: static_dir)

  case request.path_segments(req), req.method {
    [], Get -> wisp.html_response(page(), 200)
    ["api", "state"], Get -> respond(current_state([]))
    ["api", "state"], Put -> apply(req)
    ["api", "state"], _ -> wisp.method_not_allowed([Get, Put])
    _, _ -> wisp.not_found()
  }
}

fn apply(req: Request) -> Response {
  use body <- wisp.require_json(req)
  case decode.run(body, curve_json.controls_decoder()) {
    Error(_) ->
      wisp.json_response(
        json.to_string(json.object([#("error", json.string("expected {\"controls\": [{x, y}, ...]}"))])),
        400,
      )
    Ok(controls) -> {
      let table = controls |> bezier.sample(default_steps) |> lut.from_samples
      case sysfs.apply(table) {
        Error(message) -> respond(State(..current_state([]), error: Ok(message)))
        Ok(warnings) -> {
          let warnings = case store.save(controls) {
            Ok(Nil) -> warnings
            Error(message) -> list.append(warnings, [message])
          }
          respond(current_state(warnings))
        }
      }
    }
  }
}

fn current_state(warnings: List(String)) -> State {
  let controls = store.load()
  case sysfs.read(), sysfs.read_mode() {
    Ok(table), Ok(mode) ->
      State(mode:, table: lut.points(table), controls:, warnings:, error: Error(Nil))
    Error(message), _ | _, Error(message) ->
      State(mode: -1, table: [], controls:, warnings:, error: Ok(message))
  }
}

fn respond(state: State) -> Response {
  wisp.json_response(json.to_string(curve_json.encode_state(state)), 200)
}

fn page() -> String {
  "<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<title>maccel curve editor</title>
<style>
  :root { color-scheme: dark; }
  html, body { height: 100%; }
  body { margin: 0; background: #141414; color: #ddd; font: 14px/1.4 system-ui, sans-serif; }
  .app { display: grid; grid-template-columns: 300px 1fr; gap: 16px; padding: 16px; height: 100vh; box-sizing: border-box; }
  .graph { background: #1e1e1e; border-radius: 8px; display: flex; align-items: center; justify-content: center; min-height: 0; overflow: hidden; }
  .panel { background: #1e1e1e; border-radius: 8px; padding: 16px; display: flex; flex-direction: column; gap: 12px; overflow: auto; }
  .panel h1 { font-size: 16px; margin: 0 0 4px; color: #4fd6e3; }
  .row { display: flex; gap: 8px; align-items: center; }
  label { display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: #aaa; }
  input { background: #111; color: #eee; border: 1px solid #333; border-radius: 4px; padding: 6px 8px; width: 100px; }
  button { background: #2a2a2a; color: #eee; border: 1px solid #444; border-radius: 4px; padding: 8px 12px; cursor: pointer; }
  button.primary { background: #1f5f66; border-color: #4fd6e3; }
  button:disabled { opacity: .5; cursor: default; }
  .status { font-size: 12px; color: #aaa; white-space: pre-wrap; }
  .error { color: #ff7b7b; }
  .points { display: flex; flex-direction: column; gap: 2px; max-height: 280px; overflow: auto; font-size: 12px; font-variant-numeric: tabular-nums; }
  .points button { text-align: left; padding: 4px 8px; background: transparent; border-color: transparent; }
  .points button.selected { background: #1f5f66; border-color: #4fd6e3; }
  svg { user-select: none; display: block; width: min(100%, calc((100vh - 32px) * 1000 / 680)); aspect-ratio: 1000 / 680; }
  svg text { font-size: 12px; fill: #aaa; }
  .handle { cursor: grab; }
  .dragging .handle { pointer-events: none; }
</style>
</head>
<body>
<div id=\"app\"></div>
<script type=\"module\" src=\"/static/maccel_curve_editor.js\"></script>
</body>
</html>
"
}

fn require_free_port(
  port: Int,
  next: fn() -> Result(Nil, String),
) -> Result(Nil, String) {
  case port_in_use(port) {
    True ->
      Error(
        "port "
        <> int_to_string(port)
        <> " is already in use; is another maccel_curve serve running? (try --port)",
      )
    False -> next()
  }
}

@external(erlang, "maccel_curve_ffi", "port_in_use")
fn port_in_use(port: Int) -> Bool

/// The last input speed the driver saw, in counts/ms. Polled often, so it
/// is not logged.
fn speed() -> Response {
  case read_speed("/dev/maccel") {
    Ok(raw) ->
      wisp.json_response(
        json.to_string(json.object([#("speed", json.float(lut.from_fixed(raw)))])),
        200,
      )
    Error(reason) ->
      wisp.json_response(
        json.to_string(json.object([#("error", json.string("cannot read /dev/maccel: " <> reason))])),
        503,
      )
  }
}

@external(erlang, "maccel_curve_ffi", "read_speed")
fn read_speed(path: String) -> Result(Int, String)

// LIVE SPEED STREAM -----------------------------------------------------------

/// Period of the stream in milliseconds (100 samples a second).
const stream_period = 10

type Tick {
  Tick
}

/// Server-sent events: the last input speed the driver saw, pushed every
/// `stream_period` ms. The browser opens this once with EventSource and
/// gets samples with no polling round trips.
fn speed_stream(
  req: HttpRequest(mist.Connection),
) -> response.Response(mist.ResponseData) {
  mist.server_sent_events(
    request: req,
    initial_response: response.new(200),
    init: fn(subject) {
      process.send_after(subject, stream_period, Tick)
      subject
    },
    loop: fn(subject, _tick, conn) {
      let speed = case read_speed("/dev/maccel") {
        Ok(raw) -> lut.from_fixed(raw)
        Error(_) -> -1.0
      }
      let event = mist.event(string_tree.from_string(float_to_string(speed)))
      case mist.send_event(conn, event) {
        Ok(Nil) -> {
          process.send_after(subject, stream_period, Tick)
          actor.continue(subject)
        }
        Error(Nil) -> actor.stop()
      }
    },
  )
}

@external(erlang, "erlang", "float_to_binary")
fn float_to_string(f: Float) -> String
