//// The table: the 4 cards each side can play next, visible to both sides.
//// A card's value on the table can be lowered (opponent defence) or raised
//// (own buffs) before it's played.
////
//// Targeting is automatic and pure: given a scope, a change and a seed,
//// `affect` returns the new table. Random picks use the game's seeded RNG.

import gleam/float
import gleam/int
import gleam/list
import robots/rules/amount
import robots/rules/card.{type Card, type Scope, All, One}
import robots/rules/rng.{type Seed}

pub type Slot {
  /// `value` is the card's value at time `since` (ms); `card.value` is its
  /// printed value. Only growing cards (drones, a Compress) change with
  /// time; see `value_at`.
  Slot(card: Card, value: Float, since: Int)
}

/// A card on the table since time 0 (tests).
pub fn slot(card: Card) -> Slot {
  Slot(card:, value: card.value, since: 0)
}

/// A card put on the table at time `at` (drawn, or a launched drone). A
/// growing card starts growing then.
pub fn placed(card: Card, at: Int) -> Slot {
  Slot(card:, value: card.value, since: at)
}

/// The slot's value at time `now`: growing cards gain value over time up to
/// their cap (never lose any: a card already above it stays there).
pub fn value_at(slot: Slot, now: Int) -> Float {
  case card.growth(slot.card) {
    Ok(#(per_second, cap)) if slot.value <. cap -> {
      let elapsed = int.to_float(now - slot.since) /. 1000.0
      float.min(cap, slot.value +. per_second *. elapsed)
    }
    _ -> slot.value
  }
}

/// Fix the slot's value at `now`, so later changes apply to the current value.
pub fn settle(slot: Slot, now: Int) -> Slot {
  Slot(..slot, value: value_at(slot, now), since: now)
}

pub fn is_drone(slot: Slot) -> Bool {
  card.has(slot.card, card.Drone)
}

/// A card that was lowered to 0 can be burnt. Cards printed at 0 (a Launch
/// drone, a Fire card) can't.
pub fn burnable(slot: Slot) -> Bool {
  amount.is_zero(slot.value) && slot.card.value >. 0.0
}

/// Apply `change` to the table cards that `scope` selects. Returns the new
/// table and how many cards were affected (0 = the card had no target).
///
/// A single-target card only considers cards the change would actually alter,
/// so a defence never "wastes" itself on a card that is already at 0.
pub fn affect(
  table: List(Slot),
  scope: Scope,
  change: fn(Slot) -> Float,
  seed: Seed,
) -> #(List(Slot), Int, Seed) {
  let targets = candidates(table, scope, change)
  case scope, targets {
    All(_), _ -> #(
      update_at(table, targets, change),
      list.length(targets),
      seed,
    )
    One(_), [] -> #(table, 0, seed)
    One(_), _ -> {
      let #(pick, seed) = rng.int_below(seed, list.length(targets))
      let target = list.drop(targets, pick) |> list.take(1)
      #(update_at(table, target, change), 1, seed)
    }
  }
}

/// The indexes of the cards `scope` could affect: for `All`, every match;
/// for `One`, the matches `change` would actually alter (one of them is
/// picked at random).
pub fn candidates(
  table: List(Slot),
  scope: Scope,
  change: fn(Slot) -> Float,
) -> List(Int) {
  table
  |> list.index_map(fn(s, i) { #(i, s) })
  |> list.filter(fn(pair) {
    let s = pair.1
    case scope {
      All(tags) -> card.matches(s.card, tags)
      One(tags) -> card.matches(s.card, tags) && change(s) != s.value
    }
  })
  |> list.map(fn(pair) { pair.0 })
}

fn update_at(
  table: List(Slot),
  indexes: List(Int),
  change: fn(Slot) -> Float,
) -> List(Slot) {
  list.index_map(table, fn(s, i) {
    case list.contains(indexes, i) {
      True -> Slot(..s, value: change(s))
      False -> s
    }
  })
}
