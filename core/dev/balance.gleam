//// Balance report: AI-vs-AI matches with the starter robots.
////
////     cd core && gleam run -m balance
////
//// Each matchup is played with both seatings (P1/P2 swapped) so going first
//// can't skew the result. All numbers are shown on the default display scale.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import robots/card.{type Card}
import robots/catalog
import robots/efficiency
import robots/game.{type Side, P1, P2, Won}
import robots/robot.{type Robot}
import robots/scale
import robots/simulation.{type Outcome}

const matches_per_seating = 100

const think_ms = 1600

pub fn main() -> Nil {
  let config = game.default_config()
  let s = scale.default()
  io.println("BALANCE REPORT (display scale x" <> f1(s.value) <> ")")
  io.println(
    "energy "
    <> f1(config.energy_rate *. s.cost)
    <> "/s, start "
    <> int.to_string(scale.cost(s, config.starting_energy))
    <> " · AI think "
    <> f1(int.to_float(think_ms) /. 1000.0)
    <> "s · targets: ~120s matches, ~4s per move",
  )
  matchup(config, catalog.tinker(), catalog.scrapper())
  mirror(config, catalog.tinker())
  mirror(config, catalog.scrapper())
}

// MATCHUPS --------------------------------------------------------------------

/// One robot's view of a match: did it win, how many moves, etc.
type Seat {
  Seat(won: Bool, duration_ms: Int, plays: List(simulation.Play), side: Side)
}

fn matchup(config: game.Config, a: Robot, b: Robot) -> Nil {
  let as_p1 = simulation.series(config, a, b, matches_per_seating, think_ms)
  let as_p2 = simulation.series(config, b, a, matches_per_seating, think_ms)
  let seats_a =
    list.append(list.map(as_p1, seat(_, P1)), list.map(as_p2, seat(_, P2)))
  let seats_b =
    list.append(list.map(as_p1, seat(_, P2)), list.map(as_p2, seat(_, P1)))
  let all = list.append(as_p1, as_p2)
  let n = list.length(all)

  io.println(
    "\n== "
    <> a.name
    <> " vs "
    <> b.name
    <> " ("
    <> int.to_string(n)
    <> " matches)",
  )
  io.println(
    "  "
    <> a.name
    <> " wins "
    <> int.to_string(percent(list.count(seats_a, fn(x) { x.won }), n))
    <> "%   "
    <> length_summary(all)
    <> stalemates(all),
  )
  robot_line(a, seats_a)
  robot_line(b, seats_b)
  io.println("")
  card_table([#(a, seats_a), #(b, seats_b)], n)
}

fn mirror(config: game.Config, bot: Robot) -> Nil {
  let all = simulation.series(config, bot, bot, matches_per_seating, think_ms)
  let p1 = list.count(all, fn(o) { o.status == Won(P1) })
  io.println(
    "\n== Mirror "
    <> bot.name
    <> ": P1 wins "
    <> int.to_string(percent(p1, list.length(all)))
    <> "% (fair: 50% ± 5%)   "
    <> length_summary(all)
    <> stalemates(all),
  )
}

fn seat(outcome: Outcome, side: Side) -> Seat {
  Seat(
    won: outcome.status == Won(side),
    duration_ms: outcome.duration_ms,
    plays: list.filter(outcome.plays, fn(p) { p.side == side }),
    side:,
  )
}

fn length_summary(all: List(Outcome)) -> String {
  let secs = list.map(all, fn(o) { o.duration_ms / 1000 })
  "length avg "
  <> int.to_string(average_int(secs))
  <> "s (min "
  <> int.to_string(list.fold(secs, 1_000_000, int.min))
  <> ", max "
  <> int.to_string(list.fold(secs, 0, int.max))
  <> ")"
}

fn stalemates(all: List(Outcome)) -> String {
  case list.count(all, fn(o) { o.status == game.Running }) {
    0 -> ""
    k -> "   STALEMATES: " <> int.to_string(k)
  }
}

fn robot_line(bot: Robot, seats: List(Seat)) -> Nil {
  let n = int.to_float(list.length(seats))
  let moves = list.fold(seats, 0, fn(t, x) { t + list.length(x.plays) })
  let time = list.fold(seats, 0, fn(t, x) { t + x.duration_ms })
  let damage =
    list.fold(seats, 0.0, fn(t, x) {
      t
      +. {
        x.plays
        |> list.filter(fn(p) { efficiency.role(p.card) == efficiency.Damage })
        |> list.fold(0.0, fn(t, p) { t +. p.effect })
      }
    })
  let sec_per_move = int.to_float(time) /. 1000.0 /. int.to_float(moves)
  io.println(
    "  "
    <> string.pad_end(bot.name, 10, " ")
    <> bot.chassis
    <> " · HP "
    <> int.to_string(scale.value(scale.default(), bot.max_hp))
    <> " · cap "
    <> int.to_string(scale.cost(scale.default(), bot.energy_cap))
    <> " · "
    <> f1(sec_per_move)
    <> "s per move · "
    <> f1(int.to_float(moves) /. n)
    <> " moves/match · deals "
    <> int.to_string(scale.value(scale.default(), damage /. n))
    <> " damage/match",
  )
}

// CARDS -----------------------------------------------------------------------

type CardStats {
  CardStats(card: Card, plays: Int, effect: Float, misses: Int)
}

fn card_table(robots: List(#(Robot, List(Seat))), matches: Int) -> Nil {
  io.println(
    "  "
    <> pad("robot", 10)
    <> pad("card", 15)
    <> pad("role", 11)
    <> lpad("cost", 5)
    <> lpad("value", 6)
    <> lpad("goal", 6)
    <> lpad("rating", 8)
    <> lpad("plays/m", 9)
    <> lpad("avg eff", 9)
    <> lpad("real/c", 8)
    <> lpad("no-tgt", 8),
  )
  list.each(robots, fn(entry) {
    let #(bot, seats) = entry
    seats
    |> list.flat_map(fn(x) { x.plays })
    |> list.fold(dict.new(), add_play)
    |> dict.values
    |> list.sort(fn(a, b) { string.compare(a.card.name, b.card.name) })
    |> list.each(card_row(bot, _, matches / 2))
  })
  io.println(
    "\n  rating = printed value/cost (All counts "
    <> f1(efficiency.expected_all_targets)
    <> " targets); real/c = achieved effect per cost"
    <> "\n  goal = target rating for the card's role and cost (see robots/efficiency)",
  )
}

fn add_play(
  acc: Dict(String, CardStats),
  p: simulation.Play,
) -> Dict(String, CardStats) {
  let current = case dict.get(acc, p.card.name) {
    Ok(stats) -> stats
    Error(Nil) -> CardStats(p.card, 0, 0.0, 0)
  }
  let miss = case p.targets {
    0 -> 1
    _ -> 0
  }
  dict.insert(
    acc,
    p.card.name,
    CardStats(
      ..current,
      plays: current.plays + 1,
      effect: current.effect +. p.effect,
      misses: current.misses + miss,
    ),
  )
}

fn card_row(bot: Robot, stats: CardStats, matches: Int) -> Nil {
  let s = scale.default()
  let c = stats.card
  let plays = int.to_float(stats.plays)
  let avg = stats.effect /. plays
  io.println(
    "  "
    <> pad(bot.name, 10)
    <> pad(c.name, 15)
    <> pad(efficiency.role_name(efficiency.role(c)), 11)
    <> lpad(int.to_string(scale.cost(s, c.cost)), 5)
    <> lpad(int.to_string(scale.value(s, c.value)), 6)
    <> lpad(f2(efficiency.goal(c)), 6)
    <> lpad(f2(efficiency.rating(c)), 8)
    <> lpad(f1(plays /. int.to_float(matches)), 9)
    <> lpad(f1(avg *. s.value), 9)
    <> lpad(f2(avg /. c.cost), 8)
    <> lpad(int.to_string(percent(stats.misses, stats.plays)) <> "%", 8),
  )
}

// FORMATTING ------------------------------------------------------------------

fn percent(part: Int, whole: Int) -> Int {
  case whole {
    0 -> 0
    _ -> part * 100 / whole
  }
}

fn average_int(xs: List(Int)) -> Int {
  case xs {
    [] -> 0
    _ -> int.sum(xs) / list.length(xs)
  }
}

fn f1(x: Float) -> String {
  float.to_string(float.to_precision(x, 1))
}

fn f2(x: Float) -> String {
  float.to_string(float.to_precision(x, 2))
}

fn pad(text: String, width: Int) -> String {
  string.pad_end(text, width, " ")
}

fn lpad(text: String, width: Int) -> String {
  string.pad_start(text, width, " ")
}
