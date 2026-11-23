//// Does a counter part work against what it counters?
////
////     cd core && gleam run -m counter_check
////
//// For each counter part: take builds that would use it and carry a Shield
//// emitter (a general defence part, also weight 2), swap the Kinetic shield
//// for the counter, and play both versions against the counter's targets
//// and against other builds, on three random samples. A working counter is
//// better against its targets and may be worse against the rest.

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import robots/ai/brain
import robots/balance/simulation
import robots/construction/build_search.{type Build, Build}
import robots/construction/builder
import robots/construction/part.{type Component}
import robots/content/components
import robots/rules/game.{P1, P2, Running, Won}
import robots/rules/rng

const limits = build_search.Limits(max_card_parts: 4, max_copies: 4)

const reaction = brain.human

const pairs = 60

const opponents = 12

/// Seeds per seat per opponent.
const seeds = 4

@external(erlang, "tournament_ffi", "parallel_map")
fn parallel_map(items: List(a), f: fn(a) -> b) -> List(b) {
  list.map(items, f)
}

type Check {
  Check(
    counter: Component,
    /// Builds that would carry this counter.
    users: fn(Build) -> Bool,
    users_name: String,
    /// What it counters.
    targets: fn(Build) -> Bool,
    targets_name: String,
  )
}

const melee_weapons = ["Saw arm", "Fist"]

/// The Laser is a beam weapon: Smoke doesn't block it.
const range_weapons = ["Cannon", "Machine gun", "Missile rack"]

pub fn main() -> Nil {
  let builds = build_search.all(components.chassis(), components.all(), limits)
  let checks = [
    Check(
      counter: components.point_defence(),
      users: fn(_) { True },
      users_name: "builds",
      targets: uses(_, "Drone bay"),
      targets_name: "drone builds",
    ),
    Check(
      counter: components.smoke_launcher(),
      users: fn(b) { !uses_any(b, range_weapons) },
      users_name: "builds without range weapons",
      targets: fn(b) {
        uses_any(b, range_weapons) && !uses_any(b, melee_weapons)
      },
      targets_name: "range-only builds",
    ),
  ]
  list.each(checks, fn(c) {
    io.println(
      "== "
      <> c.counter.name
      <> " · "
      <> c.users_name
      <> " with a Kinetic shield, and the same with "
      <> c.counter.name
      <> " instead",
    )
    list.each([7, 11, 13], check(builds, c, _))
  })
}

fn check(builds: List(Build), c: Check, sample: Int) -> Nil {
  let #(shuffled, _) = rng.shuffle(builds, rng.new(sample))
  let targets = shuffled |> list.filter(c.targets) |> list.take(opponents)
  let others =
    shuffled
    |> list.filter(fn(b) { !c.targets(b) })
    |> list.take(opponents)
  let #(swapped, _) =
    builds
    |> list.filter(fn(b) { c.users(b) && uses(b, "Kinetic shield") })
    |> list.filter_map(swap(_, "Kinetic shield", c.counter))
    |> rng.shuffle(rng.new(sample))
  let swapped = list.take(swapped, pairs)

  let results =
    parallel_map(swapped, fn(pair) {
      let #(general, counter) = pair
      [
        #(score(general, targets), score(counter, targets)),
        #(score(general, others), score(counter, others)),
      ]
    })
  io.println(
    "   sample "
    <> int.to_string(sample)
    <> " ("
    <> int.to_string(list.length(results))
    <> " builds)",
  )
  list.index_map([c.targets_name, "other builds"], fn(group, i) {
    let rows = list.filter_map(results, fn(r) { list.drop(r, i) |> list.first })
    let average = fn(pick: fn(#(Float, Float)) -> Float) {
      float.sum(list.map(rows, pick)) /. int.to_float(list.length(rows))
    }
    io.println(
      "     vs "
      <> int.to_string(opponents)
      <> " "
      <> group
      <> ": Kinetic shield "
      <> pct(average(fn(r) { r.0 }))
      <> " → "
      <> c.counter.name
      <> " "
      <> pct(average(fn(r) { r.1 }))
      <> "  (better in "
      <> int.to_string(list.count(rows, fn(r) { r.1 >. r.0 }))
      <> ", worse in "
      <> int.to_string(list.count(rows, fn(r) { r.1 <. r.0 }))
      <> ")",
    )
  })
  Nil
}

fn uses_any(b: Build, names: List(String)) -> Bool {
  list.any(names, uses(b, _))
}

/// The build, and the same build with one `name` part replaced.
fn swap(
  b: Build,
  name: String,
  with: Component,
) -> Result(#(Build, Build), Nil) {
  let #(before, after) = list.split_while(b.parts, fn(p) { p.name != name })
  case after {
    [_, ..rest] -> {
      let parts = list.flatten([before, [with], rest])
      case builder.build(b.label, b.chassis, parts) {
        Ok(robot) -> Ok(#(b, Build(..b, parts:, robot:)))
        Error(_) -> Error(Nil)
      }
    }
    [] -> Error(Nil)
  }
}

fn uses(b: Build, name: String) -> Bool {
  list.any(b.parts, fn(p) { p.name == name })
}

/// Share of matches won (stalemates count half), both seats.
fn score(b: Build, against: List(Build)) -> Float {
  let config = game.default_config()
  let results =
    list.flat_map(against, fn(o) {
      list.flat_map(int.range(0, seeds, [], list.prepend), fn(seed) {
        [
          points(
            simulation.run(config, b.robot, o.robot, seed, reaction).status,
            P1,
          ),
          points(
            simulation.run(config, o.robot, b.robot, seed, reaction).status,
            P2,
          ),
        ]
      })
    })
  float.sum(results) /. int.to_float(list.length(results))
}

fn points(status: game.Status, me: game.Side) -> Float {
  case status {
    Won(side) if side == me -> 1.0
    Won(_) -> 0.0
    Running -> 0.5
  }
}

fn pct(x: Float) -> String {
  int.to_string(float.round(x *. 100.0)) <> "%"
}
