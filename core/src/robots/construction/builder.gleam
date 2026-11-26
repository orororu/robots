//// Building robots from a chassis and parts, before a match.
//// See docs/BUILDER.md.
////
//// `build` checks the hard rules and either returns a robot or every reason
//// it can't be built. `warnings` points out legal but questionable choices.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import robots/construction/part.{type Component, Battery, Body, Weapon}
import robots/construction/robot.{type Robot}
import robots/rules/amount
import robots/rules/card.{
  type Card, All, Both, Burn, Card, Launch, NoEffect, One, Opponent, OpponentHp,
  OwnHp, Self,
}

/// Decks smaller than this (chassis, parts and armor together) get a
/// `SmallDeck` warning: they play, but cycle the same few cards.
pub const minimum_deck = 16

pub type Chassis {
  Chassis(
    name: String,
    /// Base HP; armor adds to it.
    hp: Float,
    /// Total weight it can carry.
    capacity: Float,
    /// One entry per weapon mount: the heaviest weapon it can hold.
    weapon_mounts: List(Float),
    /// Cards every robot on this chassis has, whatever is installed: its
    /// mobility and identity. They also keep one-weapon builds from having
    /// decks made only of attacks.
    cards: List(Card),
    /// Damage the chassis has taken and kept during a run (0 when new).
    wear: Float,
  )
}

/// The chassis' HP left after wear.
pub fn chassis_hp(chassis: Chassis) -> Float {
  float.max(0.0, chassis.hp -. chassis.wear)
}

pub type BuildError {
  Overweight(total: Float, capacity: Float)
  TooManyWeapons(count: Int, mounts: Int)
  WeaponTooHeavy(weapon: String, weight: Float, mount_limit: Float)
  /// Chassis cards alone (Kick, Ram) can't win a match in reasonable time.
  NoWeapon
  NoBattery
}

pub type Warning {
  /// A card that can never do anything with this build, e.g. a buff whose
  /// tags match none of the robot's own cards.
  DeadCard(card: String)
  /// A card that costs more energy than the batteries can hold.
  Unaffordable(card: String, cost: Float, cap: Float)
  /// Fewer cards than `minimum_deck`: it plays, but the same few cards
  /// keep coming round.
  SmallDeck(cards: Int, minimum: Int)
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
    ])
  case errors {
    [] -> Ok(assemble(name, chassis, parts))
    _ -> Error(errors)
  }
}

/// The parts that fit `chassis` (weight and weapon mounts), and those that
/// don't: weapons are tried first, then batteries, then the rest, each in
/// its order. A missing weapon or battery isn't checked here.
pub fn fit(
  chassis: Chassis,
  parts: List(Component),
) -> #(List(Component), List(Component)) {
  let rank = fn(p: Component) {
    case p.kind {
      part.Weapon -> 0
      part.Battery -> 1
      _ -> 2
    }
  }
  list.index_map(parts, fn(p, i) { #(rank(p), i, p) })
  |> list.sort(fn(a, b) {
    case int.compare(a.0, b.0) {
      order.Eq -> int.compare(a.1, b.1)
      other -> other
    }
  })
  |> list.fold(#([], []), fn(acc, t) {
    let #(kept, dropped) = acc
    let trial = list.append(kept, [t.2])
    let fits =
      list.flatten([check_weight(chassis, trial), check_weapons(chassis, trial)])
      |> list.all(fn(e) { e == NoWeapon })
    case fits {
      True -> #(trial, dropped)
      False -> #(kept, list.append(dropped, [t.2]))
    }
  })
}

/// Max HP counts every part as new; the robot starts with what its worn
/// parts have left.
fn assemble(name: String, chassis: Chassis, parts: List(Component)) -> Robot {
  let armor = parts |> list.map(part.hp) |> float.sum
  let left = parts |> list.map(part.remaining_hp) |> float.sum
  let energy_cap = parts |> list.map(part.energy_cap) |> float.sum
  let bot =
    robot.new(
      name,
      chassis: chassis.name,
      max_hp: chassis.hp +. armor,
      energy_cap:,
      components: [body(chassis), ..parts],
    )
  robot.Robot(..bot, hp: chassis_hp(chassis) +. left)
}

/// A card that damages its own robot. No build gets one now (small decks
/// used to be filled up with them); kept for the rules and tests.
pub fn malfunction() -> Card {
  Card(
    name: "Malfunction",
    tags: [],
    cost: malfunction_cost,
    value: malfunction_damage,
    target: OwnHp,
    traits: [],
  )
}

pub const malfunction_cost = 1.0

pub const malfunction_damage = 0.2

/// How many cards a build's deck has: its chassis' and parts'.
pub fn deck_size(chassis: Chassis, parts: List(Component)) -> Int {
  [body(chassis), ..parts] |> list.flat_map(part.cards) |> list.length
}

/// The chassis' own cards, as a weightless part.
pub fn body(chassis: Chassis) -> Component {
  part.new(chassis.name, Body, 0.0, chassis.cards)
}

// CHECKS ----------------------------------------------------------------------

fn check_weight(chassis: Chassis, parts: List(Component)) -> List(BuildError) {
  let total = part.total_weight(parts)
  case amount.at_least(chassis.capacity, total) {
    True -> []
    False -> [Overweight(total:, capacity: chassis.capacity)]
  }
}

/// Each weapon mount, biggest first, with the weapon it holds (if any):
/// heaviest weapon on the biggest mount, as `build` checks them. Weapons
/// beyond the mounts are left out.
pub fn mounts(
  chassis: Chassis,
  parts: List(Component),
) -> List(#(Float, Option(Component))) {
  let weapons =
    parts
    |> list.filter(fn(p) { p.kind == Weapon })
    |> list.sort(fn(a, b) { float.compare(part.weight(b), part.weight(a)) })
    |> list.map(Some)
  chassis.weapon_mounts
  |> list.sort(order.reverse(float.compare))
  |> list.index_map(fn(limit, i) {
    #(limit, list.drop(weapons, i) |> list.first |> result.unwrap(None))
  })
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
  let none = case count {
    0 -> [NoWeapon]
    _ -> []
  }
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
  list.flatten([none, too_many, too_heavy])
}

fn check_battery(parts: List(Component)) -> List(BuildError) {
  case list.any(parts, fn(p) { p.kind == Battery }) {
    True -> []
    False -> [NoBattery]
  }
}

// WARNINGS --------------------------------------------------------------------

/// Each distinct problem once, in deck order; a small deck last.
pub fn warnings(bot: Robot) -> List(Warning) {
  let size = list.length(robot.deck(bot))
  let small = case size < minimum_deck {
    True -> [SmallDeck(cards: size, minimum: minimum_deck)]
    False -> []
  }
  list.append(card_warnings(bot), small)
}

fn card_warnings(bot: Robot) -> List(Warning) {
  // Launched drones are on the table too, so buffs may target them.
  let deck =
    robot.deck(bot)
    |> list.flat_map(fn(c) {
      case c.target {
        Launch(drone) -> [c, drone]
        _ -> [c]
      }
    })
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
}

/// Only cards targeting your *own* table can be judged here; what the
/// opponent brings is unknown when building.
fn can_ever_affect(c: Card, deck: List(Card)) -> Bool {
  case c.target {
    Self(One(tags)) | Self(All(tags)) ->
      list.any(deck, fn(other) { other != c && card.matches(other, tags) })
    OpponentHp
    | Opponent(_)
    | Both(_)
    | Launch(_)
    | Burn(_)
    | NoEffect
    | OwnHp -> True
  }
}

// TEXT ------------------------------------------------------------------------

pub fn describe_error(error: BuildError) -> String {
  case error {
    Overweight(total:, capacity:) ->
      "Too heavy: weight " <> num(total) <> ", max weight " <> num(capacity)
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
    NoWeapon -> "At least one weapon is required"
    NoBattery -> "A battery is required"
  }
}

/// "12", "4.5": no trailing ".0".
fn num(x: Float) -> String {
  let rounded = float.to_precision(x, 2)
  case rounded == float.floor(rounded) {
    True -> int.to_string(float.truncate(rounded))
    False -> float.to_string(rounded)
  }
}
