//// Remembers the control polygon of the curve that was last applied, so the
//// editor can show editable handles instead of 128 sampled points.

import envoy
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import maccel_curve/curve_json
import maccel_curve/point.{type Point}
import simplifile

pub fn path() -> String {
  let config_home = case envoy.get("XDG_CONFIG_HOME") {
    Ok(dir) -> dir
    Error(Nil) -> result.unwrap(envoy.get("HOME"), ".") <> "/.config"
  }
  config_home <> "/maccel_curve/controls.json"
}

pub fn save(controls: List(Point)) -> Result(Nil, String) {
  let file = path()
  let dir = dirname(file)
  use _ <- result.try(
    simplifile.create_directory_all(dir)
    |> result.map_error(fn(e) {
      "could not create " <> dir <> ": " <> simplifile.describe_error(e)
    }),
  )
  simplifile.write(file, json.to_string(curve_json.encode_points(controls)))
  |> result.map_error(fn(e) {
    "could not write " <> file <> ": " <> simplifile.describe_error(e)
  })
}

/// The saved polygon, or an empty list when nothing was saved yet.
pub fn load() -> List(Point) {
  simplifile.read(path())
  |> result.replace_error(Nil)
  |> result.try(fn(text) {
    json.parse(text, curve_json.points_decoder()) |> result.replace_error(Nil)
  })
  |> result.unwrap([])
}

fn dirname(file: String) -> String {
  case string.split(file, "/") |> list.reverse {
    [_, ..parents] -> parents |> list.reverse |> string.join("/")
    [] -> "."
  }
}
