//// Does a counter part work against what it counters?
////
////     cd core && gleam run -m counter_check
////
//// Takes builds that carry a Shield emitter (a general defence part, also
//// weight 2), swaps it for Point defence, and plays both versions against
//// drone builds and against other builds, on three random samples. A
//// working counter is better against drone builds and may be worse against
//// the rest.

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import robots/build_search.{type Build, Build}
import robots/builder
import robots/catalog
import robots/game.{P1, P2, Running, Won}
import robots/part.{type Component}
import robots/rng
import robots/simulation

const limits = build_search.Limits(max_card_parts: 4, max_copies: 4)

const think_ms = 1600

const pairs = 60

const opponents = 12

/// Seeds per seat per opponent.
const seeds = 4

@external(erlang, "tournament_ffi", "parallel_map")
fn parallel_map(items: List(a), f: fn(a) -> b) -> List(b) {
  list.map(items, f)
}

pub fn main() -> Nil {
  let builds = build_search.all(catalog.chassis(), catalog.components(), limits)
  list.each([7, 11, 13], check(builds, _))
}

fn check(builds: List(Build), sample: Int) -> Nil {
  let #(shuffled, _) = rng.shuffle(builds, rng.new(sample))
  let drone_builds =
    shuffled |> list.filter(uses(_, "Drone bay")) |> list.take(opponents)
  let other_builds =
    shuffled
    |> list.filter(fn(b) { !uses(b, "Drone bay") })
    |> list.take(opponents)
  let #(swapped, _) =
    builds
    |> list.filter(uses(_, "Shield emitter"))
    |> list.filter_map(swap(_, "Shield emitter", catalog.point_defence()))
    |> rng.shuffle(rng.new(sample))
  let swapped = list.take(swapped, pairs)

  let results =
    parallel_map(swapped, fn(pair) {
      let #(general, counter) = pair
      [
        #(score(general, drone_builds), score(counter, drone_builds)),
        #(score(general, other_builds), score(counter, other_builds)),
      ]
    })
  io.println(
    "POINT DEFENCE CHECK (sample "
    <> int.to_string(sample)
    <> ") · "
    <> int.to_string(list.length(results))
    <> " builds with a Shield emitter, and the same builds with Point defence instead",
  )
  list.index_map(["drone builds", "other builds"], fn(group, i) {
    let rows = list.filter_map(results, fn(r) { list.drop(r, i) |> list.first })
    let average = fn(pick: fn(#(Float, Float)) -> Float) {
      float.sum(list.map(rows, pick)) /. int.to_float(list.length(rows))
    }
    io.println(
      "   vs "
      <> int.to_string(opponents)
      <> " "
      <> group
      <> ": Shield emitter "
      <> pct(average(fn(r) { r.0 }))
      <> " → Point defence "
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
            simulation.run(config, b.robot, o.robot, seed, think_ms).status,
            P1,
          ),
          points(
            simulation.run(config, o.robot, b.robot, seed, think_ms).status,
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
