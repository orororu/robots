//// A tiny deterministic pseudo-random number generator (Park–Miller / MINSTD).
////
//// The seed lives inside the game state, so every shuffle is reproducible:
//// same seed + same actions = same game. That makes testing, replays and a
//// future authoritative PvP server trivial.
////
//// All intermediate values stay below 2^53, so results are identical on the
//// Erlang and JavaScript targets.

import gleam/int
import gleam/list

const modulus = 2_147_483_647

const multiplier = 48_271

pub opaque type Seed {
  Seed(state: Int)
}

pub fn new(n: Int) -> Seed {
  Seed(int.absolute_value(n) % { modulus - 1 } + 1)
}

/// Produce the next raw value in `1..modulus-1` together with the next seed.
pub fn next(seed: Seed) -> #(Int, Seed) {
  let state = seed.state * multiplier % modulus
  #(state, Seed(state))
}

/// A value in `0..n-1`.
pub fn int_below(seed: Seed, n: Int) -> #(Int, Seed) {
  let #(value, seed) = next(seed)
  #(value % n, seed)
}

pub fn shuffle(items: List(a), seed: Seed) -> #(List(a), Seed) {
  let #(seed, keyed) =
    list.map_fold(items, seed, fn(seed, item) {
      let #(key, seed) = next(seed)
      #(seed, #(key, item))
    })
  let shuffled =
    keyed
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.1 })
  #(shuffled, seed)
}
