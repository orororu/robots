//// Generating legal builds, for the build tournament (`gleam run -m
//// tournament`) and, later, for AI opponents and garage suggestions.
////
//// A build is a chassis, some *card parts* (weapons, defences, utilities,
//// batteries with cards), a plain battery if those can't pay for its
//// priciest card, and armor filling all remaining weight. Spare weight always
//// goes to armor, because that's what a player would do with it.

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component, Armor, Battery}
import robots/construction/robot.{type Robot}
import robots/rules/card

pub type Build {
  Build(label: String, chassis: Chassis, parts: List(Component), robot: Robot)
}

pub type Limits {
  Limits(max_card_parts: Int, max_copies: Int)
}

/// Parts picked for their cards: everything except armor and plain
/// (cardless) batteries.
pub fn card_parts(components: List(Component)) -> List(Component) {
  list.filter(components, fn(c) {
    c.kind != Armor && { c.kind != Battery || c.cards != [] }
  })
}

/// Every legal build without warnings, for each chassis.
pub fn all(
  chassis: List(Chassis),
  components: List(Component),
  limits: Limits,
) -> List(Build) {
  let options = card_parts(components)
  let batteries =
    components
    |> list.filter(fn(c) { c.kind == Battery && c.cards == [] })
    |> list.sort(fn(a, b) {
      float.compare(part.energy_cap(a), part.energy_cap(b))
    })
  let armors =
    components
    |> list.filter(fn(c) { c.kind == Armor })
    |> list.sort(fn(a, b) { float.compare(part.weight(b), part.weight(a)) })
  list.flat_map(chassis, fn(ch) {
    multisets(options, limits.max_card_parts, limits.max_copies)
    |> list.filter_map(complete(ch, _, batteries, armors))
  })
}

/// Add the smallest plain battery that pays for the most expensive card
/// (unless the picks' own batteries already do), then armor.
fn complete(
  chassis: Chassis,
  picks: List(Component),
  batteries: List(Component),
  armors: List(Component),
) -> Result(Build, Nil) {
  let most_expensive =
    picks
    |> list.flat_map(part.cards)
    |> list.fold(0.0, fn(m, c) { float.max(m, c.cost) })
  let own_cap = picks |> list.map(part.energy_cap) |> float.sum
  use core <- result_try(case own_cap >=. most_expensive && own_cap >. 0.0 {
    True -> Ok(picks)
    False ->
      list.find(batteries, fn(b) { part.energy_cap(b) >=. most_expensive })
      |> result.map(fn(battery) { list.append(picks, [battery]) })
  })
  let spare = chassis.capacity -. part.total_weight(core)
  let parts = list.append(core, fill(spare, armors))
  case builder.build(label(chassis, parts), chassis, parts) {
    Ok(bot) ->
      case builder.warnings(bot) {
        [] -> Ok(Build(label: bot.name, chassis:, parts:, robot: bot))
        _ -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

/// Fill spare weight with armor, heaviest pieces first.
fn fill(spare: Float, armors: List(Component)) -> List(Component) {
  case armors {
    [] -> []
    [piece, ..rest] ->
      case part.weight(piece) <=. spare +. 0.000001 {
        True -> [piece, ..fill(spare -. part.weight(piece), armors)]
        False -> fill(spare, rest)
      }
  }
}

/// All multisets of 1..max items from `options`, each item at most
/// `max_copies` times. Order inside a multiset follows `options`.
fn multisets(
  options: List(Component),
  max: Int,
  max_copies: Int,
) -> List(List(Component)) {
  pick(options, max, max_copies)
  |> list.filter(fn(set) { set != [] })
}

fn pick(
  options: List(Component),
  room: Int,
  max_copies: Int,
) -> List(List(Component)) {
  case options, room {
    _, 0 | [], _ -> [[]]
    [first, ..rest], _ -> {
      let copies = int.min(room, max_copies)
      list.repeat(0, copies + 1)
      |> list.index_map(fn(_, n) { n })
      |> list.flat_map(fn(n) {
        pick(rest, room - n, max_copies)
        |> list.map(fn(tail) { list.append(list.repeat(first, n), tail) })
      })
    }
  }
}

/// "Frame: Laser, Kinetic shield ×2 · Battery · Plating ×3"
pub fn label(chassis: Chassis, parts: List(Component)) -> String {
  let #(cards, rest) =
    list.partition(parts, fn(p) { p.kind != Battery && p.kind != Armor })
  chassis.name <> ": " <> counted(cards) <> " · " <> counted(rest)
}

fn counted(parts: List(Component)) -> String {
  parts
  |> list.map(part.display_name)
  |> list.chunk(fn(name) { name })
  |> list.map(fn(group) {
    case group {
      [name] -> name
      [name, ..] -> name <> " ×" <> int.to_string(list.length(group))
      [] -> ""
    }
  })
  |> string.join(", ")
}

/// How many cards of each role a build's deck has, for reports.
pub fn deck_size(build: Build) -> Int {
  list.length(robot.deck(build.robot))
}

pub fn average_cost(build: Build) -> Float {
  let deck = robot.deck(build.robot)
  list.fold(deck, 0.0, fn(t, c: card.Card) { t +. c.cost })
  /. int.to_float(list.length(deck))
}

fn result_try(r: Result(a, e), f: fn(a) -> Result(b, Nil)) -> Result(b, Nil) {
  case r {
    Ok(a) -> f(a)
    Error(_) -> Error(Nil)
  }
}
