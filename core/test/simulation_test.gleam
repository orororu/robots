//// Whole matches, AI against AI, with the starter robots. For the full
//// picture run `gleam run -m balance`.
////
//// Stalemates are bugs, so `every_match_ends_test` must pass. Balance is a
//// design question, so the balance checks print a warning instead of failing.

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import robots/ai/brain
import robots/balance/simulation.{type Outcome}
import robots/content/catalog
import robots/rules/game.{P1, P2, Running, Won}

const matches = 40

fn results() -> List(Outcome) {
  // Both seatings, so going first can't skew the result.
  let half = matches / 2
  let config = game.default_config()
  list.append(
    simulation.series(
      config,
      catalog.tinker(),
      catalog.scrapper(),
      half,
      brain.human,
    ),
    simulation.series(
      config,
      catalog.scrapper(),
      catalog.tinker(),
      half,
      brain.human,
    ),
  )
}

fn balance_check(ok: Bool, message: String) -> Nil {
  case ok {
    True -> Nil
    False -> io.println("\n  BALANCE WARNING: " <> message)
  }
}

pub fn every_match_ends_test() {
  assert list.all(results(), fn(o) { o.status != Running })
}

pub fn match_length_balance_test() {
  let secs = list.map(results(), fn(o) { o.duration_ms / 1000 })
  let average = int.sum(secs) / list.length(secs)
  balance_check(
    average >= 90 && average <= 150,
    "average match " <> int.to_string(average) <> "s (target ~120s)",
  )
}

pub fn move_pace_balance_test() {
  let all = results()
  let moves = list.fold(all, 0, fn(t, o) { t + list.length(o.plays) })
  let ms = list.fold(all, 0, fn(t, o) { t + o.duration_ms })
  // Two players share the match time.
  let per_move = int.to_float(ms * 2) /. int.to_float(moves) /. 1000.0
  balance_check(
    per_move >=. 3.0 && per_move <=. 5.0,
    "a move every "
      <> float.to_string(float.to_precision(per_move, 1))
      <> "s per player (target ~4s)",
  )
}

pub fn win_rate_balance_test() {
  let all = results()
  let half = matches / 2
  let tinker_wins =
    list.count(list.take(all, half), fn(o) { o.status == Won(P1) })
    + list.count(list.drop(all, half), fn(o) { o.status == Won(P2) })
  let percent = tinker_wins * 100 / matches
  balance_check(
    percent >= 35 && percent <= 65,
    "Tinker wins " <> int.to_string(percent) <> "% vs Scrapper (target 35-65%)",
  )
}
