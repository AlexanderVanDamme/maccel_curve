//// Talking to the loaded maccel kernel module through sysfs, plus the reset
//// scripts maccel's udev rule replays on boot so the table persists.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import maccel_curve/lut.{type Table}
import simplifile

const parameters_dir = "/sys/module/maccel/parameters"

const resets_dir = "/var/opt/maccel/resets"

/// Ordinal of the `lut` entry in the driver's `enum accel_mode`.
pub const lut_mode = 4

pub type Parameter {
  Parameter(name: String, value: String)
}

/// Everything that has to be written for the table to take effect.
pub fn parameters_for(table: Table) -> List(Parameter) {
  [
    Parameter("LUT_X", lut.x_param(table)),
    Parameter("LUT_Y", lut.y_param(table)),
    Parameter("MODE", int.to_string(lut_mode)),
  ]
}

/// Write the table to the driver and record it for the next boot.
/// Persisting is best effort: a failure there is reported, not fatal.
pub fn apply(table: Table) -> Result(List(String), String) {
  let params = parameters_for(table)
  use _ <- result.try(list.try_each(params, write_parameter))
  Ok(list.filter_map(params, persist))
}

fn write_parameter(p: Parameter) -> Result(Nil, String) {
  let path = parameters_dir <> "/" <> p.name
  simplifile.write(path, p.value)
  |> result.map_error(fn(e) {
    "could not write "
    <> path
    <> ": "
    <> simplifile.describe_error(e)
    <> " (is the maccel module loaded and are you in the maccel group?)"
  })
}

/// Returns a warning when the reset script could not be written.
fn persist(p: Parameter) -> Result(String, Nil) {
  let path = resets_dir <> "/set_last_" <> p.name <> "_value.sh"
  let script =
    "echo " <> p.value <> " > " <> parameters_dir <> "/" <> p.name <> ";"
  case simplifile.write(path, script) {
    Ok(Nil) -> Error(Nil)
    Error(e) ->
      Ok(
        "not persisted for reboot: could not write "
        <> path
        <> ": "
        <> simplifile.describe_error(e),
      )
  }
}

/// The table currently loaded in the driver.
pub fn read() -> Result(Table, String) {
  use xs <- result.try(read_parameter("LUT_X"))
  use ys <- result.try(read_parameter("LUT_Y"))
  use xs <- result.try(lut.parse_param(xs))
  use ys <- result.try(lut.parse_param(ys))
  Ok(lut.from_pairs(xs, ys))
}

pub fn read_mode() -> Result(Int, String) {
  use raw <- result.try(read_parameter("MODE"))
  int.parse(string.trim(raw))
  |> result.replace_error("MODE is not a number: " <> raw)
}

fn read_parameter(name: String) -> Result(String, String) {
  let path = parameters_dir <> "/" <> name
  simplifile.read(path)
  |> result.map_error(fn(e) {
    "could not read "
    <> path
    <> ": "
    <> simplifile.describe_error(e)
    <> " (is the maccel module with LUT support loaded?)"
  })
}
