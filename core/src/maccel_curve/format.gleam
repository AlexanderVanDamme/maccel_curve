//// Number formatting and parsing that behaves the same on both targets.

import gleam/float
import gleam/int
import gleam/result
import gleam/string

/// `v` with exactly `decimals` digits after the point.
pub fn fixed(v: Float, decimals: Int) -> String {
  let scale = pow10(decimals)
  let scaled = float.round(v *. int.to_float(scale))
  let sign = case scaled < 0 {
    True -> "-"
    False -> ""
  }
  let magnitude = int.absolute_value(scaled)
  let whole = magnitude / scale
  let frac = magnitude % scale
  case decimals <= 0 {
    True -> sign <> int.to_string(whole)
    False ->
      sign
      <> int.to_string(whole)
      <> "."
      <> string.pad_start(int.to_string(frac), decimals, "0")
  }
}

/// Like `fixed`, but without trailing zeros (and no trailing point).
pub fn short(v: Float, decimals: Int) -> String {
  let text = fixed(v, decimals)
  case string.contains(text, ".") {
    False -> text
    True ->
      text
      |> trim_trailing("0")
      |> trim_trailing(".")
  }
}

fn trim_trailing(text: String, suffix: String) -> String {
  case string.ends_with(text, suffix) {
    True -> trim_trailing(string.drop_end(text, string.length(suffix)), suffix)
    False -> text
  }
}

/// Parse "12", "12.5", "-0.25", " 3 ".
pub fn parse_float(text: String) -> Result(Float, Nil) {
  let text = string.trim(text)
  float.parse(text)
  |> result.lazy_or(fn() { int.parse(text) |> result.map(int.to_float) })
}

fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}
