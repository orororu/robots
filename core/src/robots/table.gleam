//// The table: the 4 cards each side can play next, visible to both sides.
//// A card's value on the table can be lowered (opponent defence) or raised
//// (own buffs) before it's played.
////
//// Targeting is automatic and pure: given a reach, a change and a seed,
//// `affect` returns the new table. Random picks use the game's seeded RNG.

import gleam/list
import robots/card.{type Card, type Reach, All, NoReach, One}
import robots/rng.{type Seed}

pub type Slot {
  /// `value` is the card's current value; `card.value` is its printed value.
  Slot(card: Card, value: Float)
}

pub fn slot(card: Card) -> Slot {
  Slot(card:, value: card.value)
}

/// Apply `change` to the table cards that `reach` targets. Returns the new
/// table and how many cards were affected (0 = the card had no target).
///
/// A single-target card only considers cards the change would actually alter,
/// so a defence never "wastes" itself on a card that is already at 0.
pub fn affect(
  table: List(Slot),
  reach: Reach,
  change: fn(Float) -> Float,
  seed: Seed,
) -> #(List(Slot), Int, Seed) {
  case reach {
    NoReach -> #(table, 0, seed)
    All(tags) -> {
      let targets =
        table
        |> list.index_map(fn(s, i) { #(i, s) })
        |> list.filter(fn(pair) { card.matches({ pair.1 }.card, tags) })
        |> list.map(fn(pair) { pair.0 })
      #(update_at(table, targets, change), list.length(targets), seed)
    }
    One(tags) -> {
      let candidates =
        table
        |> list.index_map(fn(s, i) { #(i, s) })
        |> list.filter(fn(pair) {
          let s = pair.1
          card.matches(s.card, tags) && change(s.value) != s.value
        })
        |> list.map(fn(pair) { pair.0 })
      case candidates {
        [] -> #(table, 0, seed)
        _ -> {
          let #(pick, seed) = rng.int_below(seed, list.length(candidates))
          let target = list.drop(candidates, pick) |> list.take(1)
          #(update_at(table, target, change), 1, seed)
        }
      }
    }
  }
}

fn update_at(
  table: List(Slot),
  indexes: List(Int),
  change: fn(Float) -> Float,
) -> List(Slot) {
  list.index_map(table, fn(s, i) {
    case list.contains(indexes, i) {
      True -> Slot(..s, value: change(s.value))
      False -> s
    }
  })
}
