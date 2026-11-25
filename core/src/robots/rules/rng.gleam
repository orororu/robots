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

/// Small seeds (0, 1, 2, ...) give tiny first outputs (seed × 48271), which
/// made the first shuffle keep its first card on top 96% of the time. A few
/// warm-up steps spread them across the whole range.
const warm_up_steps = 4

/// Multiplying alone keeps consecutive seeds in lockstep: their first outputs
/// differ by a constant, so e.g. `int_below(_, 3)` gave the same answer for
/// every seed. An xor-shift between steps breaks the pattern. All values stay
/// below 2^31, so bitwise operations agree on Erlang and JavaScript.
pub fn new(n: Int) -> Seed {
  warm_up(Seed(int.absolute_value(n) % { modulus - 1 } + 1), warm_up_steps)
}

fn warm_up(seed: Seed, steps: Int) -> Seed {
  case steps {
    0 -> seed
    _ -> {
      let Seed(state) = next(seed).1
      let mixed =
        int.bitwise_exclusive_or(state, int.bitwise_shift_right(state, 13))
      let mixed =
        int.bitwise_exclusive_or(
          mixed,
          int.bitwise_shift_left(mixed % 65_536, 15),
        )
      warm_up(Seed(mixed % { modulus - 1 } + 1), steps - 1)
    }
  }
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

/// The seed as a number, to save it (`from_state` restores it exactly).
pub fn to_state(seed: Seed) -> Int {
  seed.state
}

/// A seed saved with `to_state`. Unlike `new`, no warm-up: the same seed.
pub fn from_state(state: Int) -> Seed {
  case state >= 1 && state < modulus {
    True -> Seed(state)
    False -> new(state)
  }
}
