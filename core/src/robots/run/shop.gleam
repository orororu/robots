//// What a repair shop sells (see docs/RUN.md): a few new parts, a little
//// better than the level's loot, and used robots of the level's theme,
//// stripped down until the player could pay for them. No chassis alone:
//// those come from strong enemies (wrecks) and bosses.

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/content/enemies
import robots/rules/rng.{type Seed}
import robots/run/loot
import robots/run/price

pub type Shop {
  Shop(parts: List(Component), robots: List(Offer))
}

/// A used robot for sale: a roster build, maybe without some of its parts.
pub type Offer {
  Offer(name: String, chassis: Chassis, parts: List(Component))
}

pub const empty = Shop(parts: [], robots: [])

/// New parts on sale at each shop.
pub const part_count = 3

/// Used robots on sale at each shop, at most.
pub const robot_count = 1

/// Used robots sell for this share of their price.
pub const used_share = 0.6

/// The stock of a shop on `level`. `budget` is what the player could pay
/// (money plus what their spares would sell for): robots are stripped to
/// fit it, and left out if even their bare minimum doesn't.
pub fn stock(level: Int, budget: Int, seed: Seed) -> #(Shop, Seed) {
  let #(parts, seed) =
    list.map_fold(list.repeat(Nil, part_count), seed, fn(seed, _) {
      let #(p, seed) = loot.roll_shop(level, seed)
      #(seed, p)
    })
    |> fn(pair) { #(pair.1, pair.0) }
  let roster = enemies.level(level)
  let #(order, seed) = rng.shuffle(roster.enemies, seed)
  let robots =
    order
    |> list.filter_map(fn(e) { fit(Offer(e.name, e.chassis, e.parts), budget) })
    |> list.take(robot_count)
  #(Shop(parts:, robots:), seed)
}

pub fn part_price(p: Component) -> Int {
  price.of(p)
}

pub fn robot_price(offer: Offer) -> Int {
  used(
    price.of_chassis(offer.chassis) + int.sum(list.map(offer.parts, price.of)),
  )
}

fn used(full: Int) -> Int {
  float.round(int.to_float(full) *. used_share)
}

/// The robot with parts taken off, least needed first (armor, then
/// utilities, then defences, then spare weapons and batteries), until it
/// costs at most `budget`. It always keeps a weapon and a battery.
pub fn fit(offer: Offer, budget: Int) -> Result(Offer, Nil) {
  case robot_price(offer) <= budget {
    True -> Ok(offer)
    False ->
      case strip_one(offer.parts) {
        Ok(parts) -> fit(Offer(..offer, parts:), budget)
        Error(Nil) -> Error(Nil)
      }
  }
}

/// Remove the most expensive part of the least needed kind that can go.
fn strip_one(parts: List(Component)) -> Result(List(Component), Nil) {
  let count = fn(kind) { list.count(parts, fn(p) { p.kind == kind }) }
  let removable = fn(p: Component) {
    case p.kind {
      part.Armor | part.Utility | part.Defence -> True
      part.Weapon -> count(part.Weapon) > 1
      part.Battery -> count(part.Battery) > 1
      part.Body -> False
    }
  }
  let rank = fn(p: Component) {
    case p.kind {
      part.Armor -> 0
      part.Utility -> 1
      part.Defence -> 2
      part.Weapon -> 3
      part.Battery -> 4
      part.Body -> 5
    }
  }
  let indexed = list.index_map(parts, fn(p, i) { #(i, p) })
  let candidates =
    indexed
    |> list.filter(fn(pair) { removable(pair.1) })
    |> list.sort(fn(a, b) {
      case int.compare(rank(a.1), rank(b.1)) {
        order.Eq -> int.compare(price.of(b.1), price.of(a.1))
        other -> other
      }
    })
  case candidates {
    [] -> Error(Nil)
    [#(i, _), ..] ->
      Ok(
        indexed
        |> list.filter(fn(pair) { pair.0 != i })
        |> list.map(fn(p) { p.1 }),
      )
  }
}
