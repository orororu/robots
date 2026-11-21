//// Whole matches, AI against AI, with the real starter robots.
////
//// Stalemates are bugs, so `every_match_ends_test` must pass. Balance is a
//// design question, so the balance checks print a warning instead of failing
//// the run while balancing is in progress.

import gleam/int
import gleam/io
import gleam/list
import robots/ai
import robots/catalog
import robots/game.{type Game, type Status, P1, P2, Running, Won}

const step_ms = 100

const limit_ms = 600_000

const seeds = 40

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

fn results() -> List(#(Status, Int)) {
  list.repeat(0, seeds) |> list.index_map(fn(_, i) { simulate(i) })
}

/// Balance targets: print when missed, don't fail.
fn balance_check(ok: Bool, message: String) -> Nil {
  case ok {
    True -> Nil
    False -> io.println("\n  BALANCE WARNING: " <> message)
  }
}

pub fn every_match_ends_test() {
  assert list.all(results(), fn(result) { result.0 != Running })
}

pub fn match_length_balance_test() {
  let seconds = list.map(results(), fn(r) { r.1 / 1000 })
  let shortest = list.fold(seconds, limit_ms, int.min)
  let longest = list.fold(seconds, 0, int.max)
  balance_check(
    shortest >= 60 && longest <= 180,
    "matches last "
      <> int.to_string(shortest)
      <> "-"
      <> int.to_string(longest)
      <> "s (target 60-180s)",
  )
}

pub fn win_rate_balance_test() {
  let p1_wins = list.count(results(), fn(r) { r.0 == Won(P1) })
  let percent = p1_wins * 100 / seeds
  balance_check(
    percent >= 35 && percent <= 65,
    "Tinker wins " <> int.to_string(percent) <> "% vs Scrapper (target 35-65%)",
  )
}
