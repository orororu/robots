//// Upgrades, at a workshop (see docs/RUN.md): one card of a component gets
//// better.
////
//// - A card without a good attribute gets a random one (cheap ones more
////   often). A bad attribute it had (Damaged, Weak...) is replaced; Broken
////   plate cards are left alone, a repair fixes those.
//// - When every card already has a good attribute, one of them goes up a
////   tier: Tuned → Strong → Masterwork, Efficient → Rapid,
////   Overcharged → Masterwork.
//// - When every attribute is at its top tier, there's nothing to upgrade.

import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import robots/construction/attribute.{type Attribute} as a
import robots/construction/part.{type Component}
import robots/rules/card.{type Card}
import robots/rules/rng.{type Seed}

/// Good attributes a card can get, by weight.
pub fn new_attributes() -> List(#(Int, Attribute)) {
  [
    #(5, a.tuned()),
    #(5, a.efficient()),
    #(3, a.strong()),
    #(3, a.rapid()),
    #(1, a.overcharged()),
  ]
}

/// The next tier of a good attribute, if it has one.
pub fn next_tier(attribute: Attribute) -> Result(Attribute, Nil) {
  case attribute.name {
    "Tuned" -> Ok(a.strong())
    "Strong" -> Ok(a.masterwork())
    "Efficient" -> Ok(a.rapid())
    "Overcharged" -> Ok(a.masterwork())
    _ -> Error(Nil)
  }
}

/// What an upgrade did: on card `card` of the part, `attribute` (as the
/// part names it) took the place of `replaced`, if it had one; the card as
/// played before and after, and plain (no attribute).
pub type Change {
  Change(
    card: Int,
    attribute: String,
    replaced: Option(String),
    before: Card,
    after: Card,
    plain: Card,
  )
}

/// Upgrade one card of `component`, or `Error(Nil)` if none can be.
pub fn apply(
  component: Component,
  seed: Seed,
) -> Result(#(Component, Change, Seed), Nil) {
  let cards = list.index_map(component.cards, fn(c, i) { #(i, c) })
  let current = fn(i) { list.key_find(component.attributes, i) }
  let good = fn(i, c) {
    case current(i) {
      Ok(attr) -> a.is_good(attr, c)
      Error(Nil) -> False
    }
  }
  // Cards that can take a new good attribute.
  let fresh =
    list.filter_map(cards, fn(pair) {
      let #(i, c) = pair
      let options = options_for(component, i)
      case good(i, c), current(i), options {
        False, Ok(attr), [_, ..] if attr.name != "Broken" -> Ok(#(i, options))
        False, Error(Nil), [_, ..] -> Ok(#(i, options))
        _, _, _ -> Error(Nil)
      }
    })
  // Cards whose good attribute can go up a tier.
  let tiers =
    list.filter_map(cards, fn(pair) {
      let #(i, c) = pair
      case good(i, c), current(i) {
        True, Ok(attr) ->
          case next_tier(attr) {
            Ok(next) ->
              case part.can_attach(component, i, next) {
                True -> Ok(#(i, next))
                False -> Error(Nil)
              }
            Error(Nil) -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
    })
  case fresh, tiers {
    [_, ..], _ -> {
      let #(pick, seed) = rng.int_below(seed, list.length(fresh))
      let assert [#(i, options), ..] = list.drop(fresh, pick)
      let total = int.sum(list.map(options, fn(e) { e.0 }))
      let #(roll, seed) = rng.int_below(seed, total)
      Ok(attach(component, i, pick_weighted(options, roll), seed))
    }
    [], [_, ..] -> {
      let #(pick, seed) = rng.int_below(seed, list.length(tiers))
      let assert [#(i, next), ..] = list.drop(tiers, pick)
      Ok(attach(component, i, next, seed))
    }
    [], [] -> Error(Nil)
  }
}

/// Whether `apply` would do anything.
pub fn can_upgrade(component: Component) -> Bool {
  case apply(component, rng.new(0)) {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

fn options_for(component: Component, i: Int) -> List(#(Int, Attribute)) {
  case list.drop(component.cards, i) {
    [c, ..] ->
      list.filter(new_attributes(), fn(e) {
        part.can_attach(component, i, e.1) && a.is_good(e.1, c)
      })
    [] -> []
  }
}

fn attach(
  component: Component,
  i: Int,
  attribute: Attribute,
  seed: Seed,
) -> #(Component, Change, Seed) {
  let card = fn(cards) {
    let assert [c, ..] = list.drop(cards, i)
    c
  }
  let upgraded = part.attach(component, i, attribute)
  let word = fn(p) {
    part.attribute_at(p, i) |> result.map(fn(pair) { pair.0 })
  }
  let assert Ok(added) = word(upgraded)
  let change =
    Change(
      card: i,
      attribute: added,
      replaced: option.from_result(word(component)),
      before: card(part.cards(component)),
      after: card(part.cards(upgraded)),
      plain: card(part.plain_cards(component)),
    )
  #(upgraded, change, seed)
}

fn pick_weighted(entries: List(#(Int, x)), roll: Int) -> x {
  case entries {
    [#(weight, x), ..rest] ->
      case roll < weight || rest == [] {
        True -> x
        False -> pick_weighted(rest, roll - weight)
      }
    [] -> panic as "no attributes to pick from"
  }
}
