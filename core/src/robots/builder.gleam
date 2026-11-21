//// Building robots from a chassis and parts, before a match.
//// See docs/BUILDER.md.
////
//// `build` checks the hard rules and either returns a robot or every reason
//// it can't be built. `warnings` points out legal but questionable choices.

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import robots/amount
import robots/card.{type Card, All, One, Opponent, OpponentHp, Self}
import robots/part.{type Component, Battery, Weapon}
import robots/robot.{type Robot}

/// The table needs this many cards.
pub const minimum_deck = 4

pub type Chassis {
  Chassis(
    name: String,
    /// Base HP; armor adds to it.
    hp: Float,
    /// Total weight it can carry.
    capacity: Float,
    /// One entry per weapon mount: the heaviest weapon it can hold.
    weapon_mounts: List(Float),
  )
}

pub type BuildError {
  Overweight(total: Float, capacity: Float)
  TooManyWeapons(count: Int, mounts: Int)
  WeaponTooHeavy(weapon: String, weight: Float, mount_limit: Float)
  NoBattery
  DeckTooSmall(cards: Int, minimum: Int)
}

pub type Warning {
  /// A card that can never do anything with this build, e.g. a buff whose
  /// tags match none of the robot's own cards.
  DeadCard(card: String)
  /// A card that costs more energy than the batteries can hold.
  Unaffordable(card: String, cost: Float, cap: Float)
  /// No card damages the opponent: this robot can never win.
  NoDamage
}

pub fn build(
  name: String,
  chassis: Chassis,
  parts: List(Component),
) -> Result(Robot, List(BuildError)) {
  let errors =
    list.flatten([
      check_weight(chassis, parts),
      check_weapons(chassis, parts),
      check_battery(parts),
      check_deck(parts),
    ])
  case errors {
    [] -> Ok(assemble(name, chassis, parts))
    _ -> Error(errors)
  }
}

fn assemble(name: String, chassis: Chassis, parts: List(Component)) -> Robot {
  let armor = parts |> list.map(part.hp) |> float.sum
  let energy_cap = parts |> list.map(part.energy_cap) |> float.sum
  robot.new(
    name,
    chassis: chassis.name,
    max_hp: chassis.hp +. armor,
    energy_cap:,
    components: parts,
  )
}

// CHECKS ----------------------------------------------------------------------

fn check_weight(chassis: Chassis, parts: List(Component)) -> List(BuildError) {
  let total = part.total_weight(parts)
  case amount.at_least(chassis.capacity, total) {
    True -> []
    False -> [Overweight(total:, capacity: chassis.capacity)]
  }
}

/// Heaviest weapon goes on the biggest mount, and so on down. This greedy
/// pairing finds a fit whenever one exists.
fn check_weapons(chassis: Chassis, parts: List(Component)) -> List(BuildError) {
  let weapons =
    parts
    |> list.filter(fn(p) { p.kind == Weapon })
    |> list.sort(fn(a, b) { float.compare(part.weight(b), part.weight(a)) })
  let mounts = list.sort(chassis.weapon_mounts, order.reverse(float.compare))
  let count = list.length(weapons)
  let too_many = case count > list.length(mounts) {
    True -> [TooManyWeapons(count:, mounts: list.length(mounts))]
    False -> []
  }
  let too_heavy =
    list.zip(weapons, mounts)
    |> list.filter_map(fn(pair) {
      let #(weapon, limit) = pair
      case amount.at_least(limit, part.weight(weapon)) {
        True -> Error(Nil)
        False ->
          Ok(WeaponTooHeavy(
            weapon: part.display_name(weapon),
            weight: part.weight(weapon),
            mount_limit: limit,
          ))
      }
    })
  list.append(too_many, too_heavy)
}

fn check_battery(parts: List(Component)) -> List(BuildError) {
  case list.any(parts, fn(p) { p.kind == Battery }) {
    True -> []
    False -> [NoBattery]
  }
}

fn check_deck(parts: List(Component)) -> List(BuildError) {
  let cards = parts |> list.flat_map(part.cards) |> list.length
  case cards >= minimum_deck {
    True -> []
    False -> [DeckTooSmall(cards:, minimum: minimum_deck)]
  }
}

// WARNINGS --------------------------------------------------------------------

/// Each distinct problem once, in deck order.
pub fn warnings(bot: Robot) -> List(Warning) {
  let deck = robot.deck(bot)
  let no_damage = case list.any(deck, fn(c) { c.target == OpponentHp }) {
    True -> []
    False -> [NoDamage]
  }
  list.flat_map(deck, fn(c) {
    let unaffordable = case amount.at_least(bot.energy_cap, c.cost) {
      True -> []
      False -> [Unaffordable(card: c.name, cost: c.cost, cap: bot.energy_cap)]
    }
    let dead = case can_ever_affect(c, deck) {
      True -> []
      False -> [DeadCard(card: c.name)]
    }
    list.append(unaffordable, dead)
  })
  |> list.unique
  |> list.append(no_damage)
}

/// Only cards targeting your *own* table can be judged here; what the
/// opponent brings is unknown when building.
fn can_ever_affect(c: Card, deck: List(Card)) -> Bool {
  case c.target {
    Self(One(tags)) | Self(All(tags)) ->
      list.any(deck, fn(other) { other != c && card.matches(other, tags) })
    OpponentHp | Opponent(_) -> True
  }
}

// TEXT ------------------------------------------------------------------------

pub fn describe_error(error: BuildError) -> String {
  case error {
    Overweight(total:, capacity:) ->
      "Too heavy: " <> num(total) <> " of " <> num(capacity) <> " capacity"
    TooManyWeapons(count:, mounts:) ->
      int.to_string(count)
      <> " weapons, but the chassis has "
      <> int.to_string(mounts)
      <> " weapon mounts"
    WeaponTooHeavy(weapon:, weight:, mount_limit:) ->
      weapon
      <> " weighs "
      <> num(weight)
      <> "; no free mount holds more than "
      <> num(mount_limit)
    NoBattery -> "A battery is required"
    DeckTooSmall(cards:, minimum:) ->
      "Only "
      <> int.to_string(cards)
      <> " cards; the table needs "
      <> int.to_string(minimum)
  }
}

fn num(x: Float) -> String {
  float.to_string(float.to_precision(x, 2))
}
