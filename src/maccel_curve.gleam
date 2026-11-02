//// maccel_curve: bring a Custom Curve `.ccurve` profile to the maccel
//// kernel driver's look-up table mode, and edit curves in the browser.
////
////   gleam run -- import <file.ccurve> [--apply] [--svg <out.svg>] [--steps N]
////   gleam run -- show [--svg <out.svg>]
////   gleam run -- plot <file.ccurve> <out.svg>
////   gleam run -- serve [--port N] [--static <dir>]

import argv
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import maccel_curve/bezier
import maccel_curve/ccurve
import maccel_curve/format
import maccel_curve/lut.{type Table}
import maccel_curve/plot
import maccel_curve/point.{type Point}
import maccel_curve/server
import maccel_curve/store
import maccel_curve/sysfs
import simplifile

pub fn main() -> Nil {
  case run(argv.load().arguments) {
    Ok(Nil) -> Nil
    Error(message) -> {
      io.println_error("error: " <> message)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

type Options {
  Options(
    apply: Bool,
    svg: Result(String, Nil),
    steps: Int,
    port: Int,
    static_dir: String,
  )
}

const defaults = Options(
  apply: False,
  svg: Error(Nil),
  steps: server.default_steps,
  port: server.default_port,
  static_dir: "editor/dist",
)

fn run(args: List(String)) -> Result(Nil, String) {
  case args {
    ["import", file, ..rest] -> {
      use options <- result.try(parse_options(rest, defaults))
      import_curve(file, options)
    }
    ["show", ..rest] -> {
      use options <- result.try(parse_options(rest, defaults))
      show(options)
    }
    ["plot", file, out] -> import_curve(file, Options(..defaults, svg: Ok(out)))
    ["serve", ..rest] -> {
      use options <- result.try(parse_options(rest, defaults))
      io.println(
        "maccel curve editor on http://127.0.0.1:"
        <> int.to_string(options.port)
        <> " (serving "
        <> options.static_dir
        <> ")",
      )
      server.serve(options.port, options.static_dir)
    }
    _ -> Error(usage())
  }
}

fn usage() -> String {
  string.join(
    [
      "usage:",
      "  maccel_curve import <file.ccurve> [--apply] [--svg <out.svg>] [--steps N]",
      "  maccel_curve show [--svg <out.svg>]",
      "  maccel_curve plot <file.ccurve> <out.svg>",
      "  maccel_curve serve [--port N] [--static <dir>]",
    ],
    "\n",
  )
}

fn parse_options(args: List(String), acc: Options) -> Result(Options, String) {
  case args {
    [] -> Ok(acc)
    ["--apply", ..rest] -> parse_options(rest, Options(..acc, apply: True))
    ["--svg", path, ..rest] ->
      parse_options(rest, Options(..acc, svg: Ok(path)))
    ["--static", dir, ..rest] ->
      parse_options(rest, Options(..acc, static_dir: dir))
    ["--steps", n, ..rest] ->
      case int.parse(n) {
        Ok(steps) if steps > 0 -> parse_options(rest, Options(..acc, steps:))
        _ -> Error("--steps expects a positive integer")
      }
    ["--port", n, ..rest] ->
      case int.parse(n) {
        Ok(port) if port > 0 -> parse_options(rest, Options(..acc, port:))
        _ -> Error("--port expects a positive integer")
      }
    [other, ..] -> Error("unknown argument: " <> other <> "\n" <> usage())
  }
}

fn import_curve(file: String, options: Options) -> Result(Nil, String) {
  use text <- result.try(
    simplifile.read(file)
    |> result.map_error(fn(e) {
      "could not read " <> file <> ": " <> simplifile.describe_error(e)
    }),
  )
  use curve <- result.try(ccurve.parse(text))
  let controls = curve.horizontal
  let table = controls |> bezier.sample(options.steps) |> lut.from_samples

  case curve.vertical == curve.horizontal {
    True -> Nil
    False ->
      io.println_error(
        "note: the vertical curve differs from the horizontal one; maccel applies one curve to both axes (YX_RATIO can scale y), so the horizontal curve is used.",
      )
  }

  print_controls(controls)
  print_table(table)
  use _ <- result.try(write_svg(options.svg, table, controls))
  case options.apply {
    True -> {
      use _ <- result.try(apply(table))
      case store.save(controls) {
        Ok(Nil) -> io.println("control points saved to " <> store.path())
        Error(message) -> io.println_error("warning: " <> message)
      }
      Ok(Nil)
    }
    False -> {
      io.println("dry run; add --apply to write the table to the driver")
      Ok(Nil)
    }
  }
}

fn show(options: Options) -> Result(Nil, String) {
  use table <- result.try(sysfs.read())
  use mode <- result.try(sysfs.read_mode())
  io.println(
    "driver mode: "
    <> int.to_string(mode)
    <> case mode == sysfs.lut_mode {
      True -> " (lut)"
      False -> " (not lut; the table is loaded but inactive)"
    },
  )
  print_table(table)
  write_svg(options.svg, table, [])
}

fn apply(table: Table) -> Result(Nil, String) {
  use warnings <- result.try(sysfs.apply(table))
  list.each(warnings, fn(w) { io.println_error("warning: " <> w) })
  io.println(
    "applied "
    <> int.to_string(lut.size(table))
    <> " points and switched the driver to lut mode",
  )
  Ok(Nil)
}

fn write_svg(
  target: Result(String, Nil),
  table: Table,
  controls: List(Point),
) -> Result(Nil, String) {
  case target {
    Error(Nil) -> Ok(Nil)
    Ok(path) ->
      simplifile.write(path, plot.svg(table, controls))
      |> result.map_error(fn(e) {
        "could not write " <> path <> ": " <> simplifile.describe_error(e)
      })
      |> result.map(fn(_) { io.println("plot written to " <> path) })
  }
}

fn print_controls(controls: List(Point)) -> Nil {
  io.println(
    "control points (" <> int.to_string(list.length(controls)) <> "):",
  )
  list.each(controls, fn(p) { io.println("  " <> fmt_point(p)) })
}

fn print_table(table: Table) -> Nil {
  io.println(
    "look-up table (" <> int.to_string(lut.size(table)) <> " points):",
  )
  io.println("  speed (counts/ms)  sensitivity")
  table
  |> lut.points
  |> list.each(fn(p) { io.println("  " <> fmt_point(p)) })
  io.println("")
  io.println("LUT_X=" <> lut.x_param(table))
  io.println("LUT_Y=" <> lut.y_param(table))
  io.println("MODE=" <> int.to_string(sysfs.lut_mode))
}

fn fmt_point(p: Point) -> String {
  string.pad_end(format.fixed(p.x, 3), 18, " ") <> " " <> format.fixed(p.y, 5)
}
