//// Whole matches, AI against AI, with the real starter robots. Catches
//// stalemates (e.g. both tables clogged with dead cards) and runaway balance.

import gleam/list
import robots/ai
import robots/catalog
import robots/game.{type Game, type Status, P1, P2, Running, Won}

const step_ms = 100

const limit_ms = 600_000

fn simulate(seed: Int) -> #(Status, Int) {
  let state =
    game.new(
      game.default_config(),
      p1: catalog.tinker(),
      p2: catalog.scrapper(),
      seed:,
      now: 0,
    )
  run(state, ai.new(P1, think_ms: 1600, now: 0), ai.new(P2, 1600, 0), 0)
}

fn run(state: Game, a: ai.Brain, b: ai.Brain, now: Int) -> #(Status, Int) {
  case state.status, now > limit_ms {
    Running, False -> {
      let #(a, state) = ai.act(a, state, now)
      let #(b, state) = ai.act(b, state, now)
      run(state, a, b, now + step_ms)
    }
    status, _ -> #(status, now)
  }
}

pub fn every_match_ends_test() {
  let results =
    list.map(list.repeat(0, 20) |> list.index_map(fn(_, i) { i }), simulate)
  assert list.all(results, fn(result) { result.0 != Running })
}

pub fn matches_last_a_reasonable_time_test() {
  let durations =
    list.repeat(0, 20)
    |> list.index_map(fn(_, i) { simulate(i).1 })
  // Between 15 seconds and 5 minutes of play.
  assert list.all(durations, fn(ms) { ms >= 15_000 && ms <= 300_000 })
}

pub fn both_robots_can_win_test() {
  let winners =
    list.repeat(0, 40)
    |> list.index_map(fn(_, i) { simulate(i).0 })
  assert list.contains(winners, Won(P1))
  assert list.contains(winners, Won(P2))
}
