//// Build tournament: which builds, chassis and parts win?
////
////     cd core && gleam run -m tournament
////
//// Phase 1: every legal build plays a fixed gauntlet of random opponents
//// (plus the starters), from both seats.
//// Phase 2: the best builds play a round robin with more matches each.

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import robots/build_search.{type Build}
import robots/builder.{type Chassis}
import robots/catalog
import robots/game.{P1, P2, Running, Won}
import robots/part
import robots/rng
import robots/robot.{type Robot}
import robots/scale
import robots/simulation

const limits = build_search.Limits(max_card_parts: 4, max_copies: 2)

const gauntlet_size = 24

const finalists = 24

const final_seeds = 5

const think_ms = 1600

/// One process per item on BEAM (fast; use `gleam run -m tournament`);
/// sequential on JavaScript.
@external(erlang, "tournament_ffi", "parallel_map")
fn parallel_map(items: List(a), f: fn(a) -> b) -> List(b) {
  list.map(items, f)
}

pub fn main() -> Nil {
  let builds = build_search.all(catalog.chassis(), catalog.components(), limits)
  let starters = [
    starter("Tinker (starter)", catalog.frame(), catalog.tinker()),
    starter("Scrapper (starter)", catalog.brute(), catalog.scrapper()),
  ]
  let #(shuffled, _) = rng.shuffle(builds, rng.new(42))
  let gauntlet = list.append(list.take(shuffled, gauntlet_size), starters)

  io.println(
    "BUILD TOURNAMENT · "
    <> int.to_string(list.length(builds))
    <> " legal builds (up to "
    <> int.to_string(limits.max_card_parts)
    <> " card parts, "
    <> int.to_string(limits.max_copies)
    <> " copies each; spare weight filled with armor)",
  )
  io.println(
    "Phase 1: each build vs "
    <> int.to_string(list.length(gauntlet))
    <> " gauntlet opponents, both seats",
  )

  let phase1 =
    parallel_map(list.append(builds, starters), fn(b) {
      #(b, score_against(b, gauntlet, 1))
    })
    |> list.sort(fn(a, b) { float.compare({ b.1 }.score, { a.1 }.score) })

  let stalemates = list.fold(phase1, 0, fn(t, r) { t + { r.1 }.stalemates })
  io.println(
    "  "
    <> int.to_string(list.fold(phase1, 0, fn(t, r) { t + { r.1 }.played }))
    <> " matches, "
    <> int.to_string(stalemates)
    <> " stalemates",
  )

  // PHASE 2
  let top = phase1 |> list.take(finalists) |> list.map(fn(r) { r.0 })
  io.println(
    "Phase 2: top "
    <> int.to_string(finalists)
    <> " round robin, "
    <> int.to_string(final_seeds * 2)
    <> " matches per pairing",
  )
  let phase2 =
    parallel_map(top, fn(b) {
      let others = list.filter(top, fn(o) { o.label != b.label })
      #(b, score_against(b, others, final_seeds))
    })
    |> list.sort(fn(a, b) { float.compare({ b.1 }.score, { a.1 }.score) })

  print_top(phase2)
  print_starters(phase1)
  print_chassis(phase1)
  print_parts(phase1, builds)
  print_armor(phase1)
}

fn starter(label: String, chassis: Chassis, bot: Robot) -> Build {
  build_search.Build(label:, chassis:, parts: bot.components, robot: bot)
}

// SCORING ---------------------------------------------------------------------

type Score {
  Score(score: Float, played: Int, stalemates: Int)
}

/// Share of matches won (stalemates count half), playing each opponent from
/// both seats with `seeds` seeds.
fn score_against(b: Build, opponents: List(Build), seeds: Int) -> Score {
  let config = game.default_config()
  let results =
    list.flat_map(opponents, fn(o) {
      list.repeat(0, seeds)
      |> list.index_map(fn(_, seed) { seed })
      |> list.flat_map(fn(seed) {
        let as_p1 = simulation.run(config, b.robot, o.robot, seed, think_ms)
        let as_p2 = simulation.run(config, o.robot, b.robot, seed, think_ms)
        [points(as_p1.status, P1), points(as_p2.status, P2)]
      })
    })
  let played = list.length(results)
  Score(
    score: float.sum(results) /. int.to_float(played),
    played:,
    stalemates: list.count(results, fn(p) { p == 0.5 }),
  )
}

fn points(status: game.Status, me: game.Side) -> Float {
  case status {
    Won(side) if side == me -> 1.0
    Won(_) -> 0.0
    Running -> 0.5
  }
}

// REPORTS ---------------------------------------------------------------------

fn print_top(results: List(#(Build, Score))) -> Nil {
  io.println("\n== Top builds (phase 2 round robin)")
  io.println(
    "   "
    <> lpad("win", 5)
    <> lpad("HP", 5)
    <> lpad("cap", 5)
    <> lpad("cards", 6)
    <> lpad("avg$", 6)
    <> "  build",
  )
  results
  |> list.take(15)
  |> list.index_map(fn(r, i) {
    let #(b, s) = r
    io.println(
      lpad(int.to_string(i + 1), 2)
      <> " "
      <> lpad(pct(s.score), 5)
      <> lpad(int.to_string(scale.value(scale.default(), b.robot.max_hp)), 5)
      <> lpad(int.to_string(scale.cost(scale.default(), b.robot.energy_cap)), 5)
      <> lpad(int.to_string(build_search.deck_size(b)), 6)
      <> lpad(
        int.to_string(scale.cost(scale.default(), build_search.average_cost(b))),
        6,
      )
      <> "  "
      <> b.label,
    )
  })
  Nil
}

fn print_starters(results: List(#(Build, Score))) -> Nil {
  io.println("\n== Starters (phase 1)")
  let n = list.length(results)
  results
  |> list.index_map(fn(r, i) { #(r, i) })
  |> list.filter(fn(x) { string.contains(x.0.0.label, "starter") })
  |> list.each(fn(x) {
    let #(#(b, s), rank) = x
    io.println(
      "   "
      <> pad(b.label, 20)
      <> pct(s.score)
      <> " · rank "
      <> int.to_string(rank + 1)
      <> " of "
      <> int.to_string(n)
      <> " (top "
      <> int.to_string({ rank + 1 } * 100 / n)
      <> "%)",
    )
  })
}

fn print_chassis(results: List(#(Build, Score))) -> Nil {
  io.println("\n== Chassis (phase 1)")
  io.println(
    "   "
    <> pad("chassis", 8)
    <> lpad("builds", 7)
    <> lpad("best", 6)
    <> lpad("median", 8)
    <> lpad("in top 10%", 12),
  )
  let top_n = list.length(results) / 10
  let top = list.take(results, top_n)
  list.each(catalog.chassis(), fn(ch) {
    let mine =
      results
      |> list.filter(fn(r) { { r.0 }.chassis == ch })
      |> list.map(fn(r) { { r.1 }.score })
    let in_top = list.count(top, fn(r) { { r.0 }.chassis == ch })
    io.println(
      "   "
      <> pad(ch.name, 8)
      <> lpad(int.to_string(list.length(mine)), 7)
      <> lpad(pct(list.first(mine) |> unwrap), 6)
      <> lpad(pct(median(mine)), 8)
      <> lpad(int.to_string(in_top * 100 / int.max(top_n, 1)) <> "%", 12),
    )
  })
}

/// For each card part: how much more often it shows up in the top 10% than
/// in builds overall (lift), and the average score of builds using it.
fn print_parts(results: List(#(Build, Score)), builds: List(Build)) -> Nil {
  io.println(
    "\n== Parts (phase 1) · lift > 1: favoured by winners, < 1: avoided",
  )
  io.println(
    "   "
    <> pad("part", 20)
    <> pad("kind", 9)
    <> lpad("weight", 7)
    <> lpad("in all", 8)
    <> lpad("in top", 8)
    <> lpad("lift", 6)
    <> lpad("avg score", 11),
  )
  let top_n = list.length(results) / 10
  let top = list.take(results, top_n)
  let uses = fn(b: Build, name: String) {
    list.any(b.parts, fn(p) { p.name == name })
  }
  catalog.components()
  |> build_search.card_parts
  |> list.map(fn(p) {
    let all_share =
      int.to_float(list.count(builds, uses(_, p.name)))
      /. int.to_float(list.length(builds))
    let top_share =
      int.to_float(list.count(top, fn(r) { uses(r.0, p.name) }))
      /. int.to_float(int.max(top_n, 1))
    let scores =
      results
      |> list.filter(fn(r) { uses(r.0, p.name) })
      |> list.map(fn(r) { { r.1 }.score })
    #(p, all_share, top_share, average(scores))
  })
  |> list.sort(fn(a, b) {
    float.compare(b.2 /. float.max(b.1, 0.0001), a.2 /. float.max(a.1, 0.0001))
  })
  |> list.each(fn(row) {
    let #(p, all_share, top_share, avg) = row
    io.println(
      "   "
      <> pad(p.name, 20)
      <> pad(part.kind_name(p.kind), 9)
      <> lpad(f1(part.weight(p)), 7)
      <> lpad(pct(all_share), 8)
      <> lpad(pct(top_share), 8)
      <> lpad(f1(top_share /. float.max(all_share, 0.0001)), 6)
      <> lpad(pct(avg), 11),
    )
  })
}

/// Is weight priced right? If winners carry much more (or less) armor than
/// average, card parts are too weak (or too strong) for their weight.
fn print_armor(results: List(#(Build, Score))) -> Nil {
  let armor_weight = fn(b: Build) {
    b.parts
    |> list.filter(fn(p) { p.kind == part.Armor })
    |> part.total_weight
  }
  let share = fn(rs: List(#(Build, Score))) {
    average(
      list.map(rs, fn(r) { armor_weight(r.0) /. { r.0 }.chassis.capacity }),
    )
  }
  let n = list.length(results)
  io.println("\n== Armor share of capacity (weight pricing check)")
  io.println(
    "   top 10%: "
    <> pct(share(list.take(results, n / 10)))
    <> " · all: "
    <> pct(share(results))
    <> " · bottom 10%: "
    <> pct(share(list.drop(results, n - n / 10))),
  )
  io.println(
    "   much more armor at the top → card parts are too weak for their weight",
  )
}

// HELPERS ---------------------------------------------------------------------

fn median(xs: List(Float)) -> Float {
  let sorted = list.sort(xs, float.compare)
  list.drop(sorted, list.length(sorted) / 2) |> list.first |> unwrap
}

fn average(xs: List(Float)) -> Float {
  case xs {
    [] -> 0.0
    _ -> float.sum(xs) /. int.to_float(list.length(xs))
  }
}

fn unwrap(r: Result(Float, Nil)) -> Float {
  case r {
    Ok(x) -> x
    Error(Nil) -> 0.0
  }
}

fn pct(x: Float) -> String {
  int.to_string(float.round(x *. 100.0)) <> "%"
}

fn f1(x: Float) -> String {
  float.to_string(float.to_precision(x, 1))
}

fn pad(text: String, width: Int) -> String {
  string.pad_end(text, width, " ")
}

fn lpad(text: String, width: Int) -> String {
  string.pad_start(text, width, " ")
}
