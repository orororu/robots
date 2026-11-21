//// Energy is never "ticked". We store the amount at the last change and the
//// time of that change; the current amount is computed from the clock.
//// No game loop is needed to keep it correct, and it's trivially testable.

import gleam/float
import gleam/int

pub type Energy {
  Energy(base: Float, since: Int, rate: Float, cap: Float)
}

/// `rate` is energy per second, `now` is milliseconds.
pub fn new(
  start: Float,
  rate rate: Float,
  cap cap: Float,
  now now: Int,
) -> Energy {
  Energy(base: float.min(start, cap), since: now, rate:, cap:)
}

pub fn at(energy: Energy, now: Int) -> Float {
  let elapsed = int.max(0, now - energy.since)
  let gained = energy.rate *. int.to_float(elapsed) /. 1000.0
  float.min(energy.cap, energy.base +. gained)
}

/// Spend energy, or fail with the amount currently available.
pub fn spend(energy: Energy, amount: Float, now: Int) -> Result(Energy, Float) {
  let current = at(energy, now)
  case current >=. amount {
    True -> Ok(rebase(energy, current -. amount, now))
    False -> Error(current)
  }
}

pub fn gain(energy: Energy, amount: Float, now: Int) -> Energy {
  rebase(energy, float.min(energy.cap, at(energy, now) +. amount), now)
}

/// Change how fast energy accumulates from `now` on (e.g. an overclock card).
pub fn set_rate(energy: Energy, rate: Float, now: Int) -> Energy {
  Energy(..rebase(energy, at(energy, now), now), rate:)
}

// A stale `now` (earlier than the last change) must never grant extra energy.
fn rebase(energy: Energy, base: Float, now: Int) -> Energy {
  Energy(..energy, base:, since: int.max(energy.since, now))
}
