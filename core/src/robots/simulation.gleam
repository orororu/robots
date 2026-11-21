//// AI-vs-AI matches for balancing. Pure: same seeds, same results.
//// Used by `test/simulation_test.gleam` and the `dev/balance.gleam` report.

import gleam/list
import robots/ai
import robots/card.{type Card}
import robots/game.{type Game, type Side, type Status, P1, P2, Played, Running}
import robots/robot.{type Robot}

pub type Play {
  Play(
    side: Side,
    card: Card,
    value: Float,
    targets: Int,
    effect: Float,
    at: Int,
  )
}

pub type Outcome {
  Outcome(status: Status, duration_ms: Int, plays: List(Play))
}

const step_ms = 100

/// Matches still running after this are reported as `Running` (stalemate).
pub const limit_ms = 900_000

pub fn run(
  config: game.Config,
  p1: Robot,
  p2: Robot,
  seed: Int,
  think_ms: Int,
) -> Outcome {
  let state = game.new(config, p1:, p2:, seed:, now: 0)
  let a = ai.new(P1, think_ms:, now: 0)
  let b = ai.new(P2, think_ms:, now: 0)
  loop(state, a, b, 0, [])
}

/// Many seeds at once: `0..count-1`.
pub fn series(
  config: game.Config,
  p1: Robot,
  p2: Robot,
  count: Int,
  think_ms: Int,
) -> List(Outcome) {
  list.repeat(0, count)
  |> list.index_map(fn(_, seed) { run(config, p1, p2, seed, think_ms) })
}

fn loop(
  state: Game,
  a: ai.Brain,
  b: ai.Brain,
  now: Int,
  plays: List(Play),
) -> Outcome {
  case state.status, now > limit_ms {
    Running, False -> {
      let #(a, after_a) = ai.act(a, state, now)
      let plays = record(state, after_a, now, plays)
      let #(b, after_b) = ai.act(b, after_a, now)
      let plays = record(after_a, after_b, now, plays)
      loop(after_b, a, b, now + step_ms, plays)
    }
    status, _ -> Outcome(status:, duration_ms: now, plays: list.reverse(plays))
  }
}

fn record(
  before: Game,
  after: Game,
  now: Int,
  plays: List(Play),
) -> List(Play) {
  case before.log == after.log, after.log {
    True, _ -> plays
    // A finishing blow logs `Destroyed` right after the `Played` event.
    False, [Played(side:, card:, value:, targets:, effect:), ..]
    | False, [_, Played(side:, card:, value:, targets:, effect:), ..]
    -> [Play(side:, card:, value:, targets:, effect:, at: now), ..plays]
    False, _ -> plays
  }
}
