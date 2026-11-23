//// Damage that stays on a robot between battles in a run (see docs/RUN.md).
////
//// In battle a robot has one HP pool. Afterwards, the damage it took is put
//// on its parts: armor first, the most worn plate first. A plate whose HP
//// runs out breaks: it stays installed, with no HP left and every card
//// Broken, so the deck keeps its size. Only damage beyond all the armor
//// reaches the chassis. Because damage stays on the part that took it,
//// swapping parts can't heal a robot.

import gleam/float
import gleam/list
import gleam/order
import robots/construction/attribute
import robots/construction/builder.{type Chassis, Chassis}
import robots/construction/part.{type Component, Armor, Component}
import robots/rules/amount

/// Put `damage` on the chassis and parts. Returns the worn chassis and the
/// parts, in the same order (plates that ran out of HP are broken).
pub fn assign(
  chassis: Chassis,
  parts: List(Component),
  damage: Float,
) -> #(Chassis, List(Component)) {
  let #(parts, left) = wear_armor(parts, damage)
  let wear = float.min(chassis.hp, chassis.wear +. left)
  #(Chassis(..chassis, wear:), parts)
}

/// Damage taken in a battle: HP at the start minus HP at the end.
pub fn taken(start_hp: Float, end_hp: Float) -> Float {
  float.max(0.0, start_hp -. end_hp)
}

fn wear_armor(
  parts: List(Component),
  damage: Float,
) -> #(List(Component), Float) {
  // Number the parts so plates can be worn in any order and the rest keep
  // their places.
  let numbered = list.index_map(parts, fn(p, i) { #(i, p) })
  let plates =
    numbered
    |> list.filter(fn(pair) { { pair.1 }.kind == Armor && !is_broken(pair.1) })
    |> list.sort(fn(a, b) { most_worn_first(a.1, b.1) })
  let #(changes, left) =
    list.fold(plates, #([], damage), fn(acc, pair) {
      let #(changes, damage) = acc
      let #(i, plate) = pair
      let remaining = part.remaining_hp(plate)
      case amount.is_zero(damage), amount.at_least(damage, remaining) {
        True, _ -> acc
        // The plate breaks; the rest of the damage goes on.
        False, True -> #([#(i, break(plate)), ..changes], damage -. remaining)
        False, False -> #(
          [#(i, Component(..plate, wear: plate.wear +. damage)), ..changes],
          0.0,
        )
      }
    })
  let parts =
    list.map(numbered, fn(pair) {
      case list.key_find(changes, pair.0) {
        Ok(changed) -> changed
        Error(Nil) -> pair.1
      }
    })
  #(parts, left)
}

/// A plate with no HP left and every card Broken (replacing any attribute
/// the card had). It keeps its weight and its place in the deck until it's
/// replaced.
pub fn break(plate: Component) -> Component {
  let plate = Component(..plate, wear: part.hp(plate))
  list.index_fold(plate.cards, plate, fn(plate, _, i) {
    part.attach(plate, i, attribute.broken())
  })
}

/// All the damage the chassis and the armor carry.
pub fn total(chassis: Chassis, parts: List(Component)) -> Float {
  list.fold(parts, chassis.wear, fn(sum, p) {
    case p.kind {
      Armor -> sum +. p.wear
      _ -> sum
    }
  })
}

/// Remove all wear: the chassis and every plate are as new, and broken
/// plates lose their Broken cards. (A card that had another attribute
/// before it broke comes back plain.)
pub fn repair(
  chassis: Chassis,
  parts: List(Component),
) -> #(Chassis, List(Component)) {
  let broken = attribute.broken()
  let parts =
    list.map(parts, fn(p) {
      case p.kind {
        Armor ->
          Component(
            ..p,
            wear: 0.0,
            attributes: list.filter(p.attributes, fn(pair) { pair.1 != broken }),
          )
        _ -> p
      }
    })
  #(Chassis(..chassis, wear: 0.0), parts)
}

/// An armor plate whose HP has run out.
pub fn is_broken(plate: Component) -> Bool {
  plate.kind == Armor
  && part.hp(plate) >. 0.0
  && amount.is_zero(part.remaining_hp(plate))
}

/// The plate with the largest share of its HP gone first; between equally
/// worn plates, the one with less HP left.
fn most_worn_first(a: Component, b: Component) -> order.Order {
  case float.compare(worn_share(b), worn_share(a)) {
    order.Eq -> float.compare(part.remaining_hp(a), part.remaining_hp(b))
    other -> other
  }
}

fn worn_share(plate: Component) -> Float {
  case part.hp(plate) >. 0.0 {
    True -> plate.wear /. part.hp(plate)
    False -> 1.0
  }
}
