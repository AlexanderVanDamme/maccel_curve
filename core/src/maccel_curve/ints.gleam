//// Small integer helpers missing from the standard library.

import gleam/int
import gleam/list

/// The integers 0, 1, ..., n (inclusive); empty when n is negative.
pub fn upto(n: Int) -> List(Int) {
  int.range(from: 0, to: n + 1, with: [], run: list.prepend)
  |> list.reverse
}
