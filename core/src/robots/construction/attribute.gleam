//// Card attributes: loot quality on single cards (see docs/RUN.md).
////
//// A looted part's cards can each carry one attribute, e.g. a Machine gun
//// whose Burst is "Rapid" (cheaper) and whose Sweep is "Broken" (almost no
//// value). The card's name gets the attribute ("Rapid Burst"), and the part's
//// name shows its two most impactful attributes ("Broken rapid machine gun").

import gleam/float
import gleam/list
import robots/balance/efficiency
import robots/rules/card.{type Card, Burn, Card, Launch, NoEffect}

pub type Attribute {
  Attribute(name: String, effect: Effect)
}

pub type Effect {
  /// Multiply the card's value and cost.
  Scale(value: Float, cost: Float)
  /// Multiply the cost and rescale the value so the card stays on its
  /// role's efficiency band at the new cost. Bigger cards are more efficient
  /// (the band's cost slope), so a resized-up card gains a little.
  Resize(cost: Float)
}

// THE TABLE -------------------------------------------------------------------

pub fn broken() -> Attribute {
  Attribute("Broken", Scale(value: 0.2, cost: 1.0))
}

pub fn damaged() -> Attribute {
  Attribute("Damaged", Scale(value: 0.6, cost: 1.0))
}

pub fn weak() -> Attribute {
  Attribute("Weak", Scale(value: 0.8, cost: 1.0))
}

pub fn worn() -> Attribute {
  Attribute("Worn", Scale(value: 0.9, cost: 1.0))
}

pub fn wasteful() -> Attribute {
  Attribute("Wasteful", Scale(value: 1.0, cost: 1.5))
}

pub fn sluggish() -> Attribute {
  Attribute("Sluggish", Scale(value: 1.0, cost: 1.2))
}

pub fn crude() -> Attribute {
  Attribute("Crude", Scale(value: 0.8, cost: 1.1))
}

pub fn tuned() -> Attribute {
  Attribute("Tuned", Scale(value: 1.1, cost: 1.0))
}

pub fn strong() -> Attribute {
  Attribute("Strong", Scale(value: 1.2, cost: 1.0))
}

pub fn masterwork() -> Attribute {
  Attribute("Masterwork", Scale(value: 1.4, cost: 1.0))
}

pub fn efficient() -> Attribute {
  Attribute("Efficient", Scale(value: 1.0, cost: 0.9))
}

pub fn rapid() -> Attribute {
  Attribute("Rapid", Scale(value: 1.0, cost: 0.8))
}

pub fn overcharged() -> Attribute {
  Attribute("Overcharged", Scale(value: 1.5, cost: 1.25))
}

pub fn precise() -> Attribute {
  Attribute("Precise", Resize(cost: 1.2))
}

pub fn quick() -> Attribute {
  Attribute("Quick", Resize(cost: 0.8))
}

/// Every attribute, worst to best.
pub fn all() -> List(Attribute) {
  [
    broken(),
    damaged(),
    wasteful(),
    crude(),
    weak(),
    sluggish(),
    worn(),
    quick(),
    precise(),
    tuned(),
    efficient(),
    strong(),
    rapid(),
    overcharged(),
    masterwork(),
  ]
}

// APPLYING --------------------------------------------------------------------

/// Whether the attribute does anything to this card. Value changes need a
/// card whose value matters (not a drone launch, Ignite or Fire); cost
/// changes need a cost.
pub fn applies_to(attribute: Attribute, c: Card) -> Bool {
  let value_matters = value_matters(c)
  case attribute.effect {
    Scale(value:, cost:) ->
      { value == 1.0 || value_matters } && { cost == 1.0 || c.cost >. 0.0 }
    Resize(_) -> value_matters && c.cost >. 0.0
  }
}

fn value_matters(c: Card) -> Bool {
  case c.target {
    Launch(_) | Burn(_) | NoEffect -> False
    _ -> c.value >. 0.0
  }
}

pub fn apply(attribute: Attribute, c: Card) -> Card {
  let changed = case attribute.effect {
    Scale(value:, cost:) ->
      Card(..c, value: c.value *. value, cost: c.cost *. cost)
    Resize(cost: factor) -> {
      let cost = c.cost *. factor
      let role = efficiency.role(c)
      let ratio =
        efficiency.goal_for(role, cost)
        *. cost
        /. { efficiency.goal_for(role, c.cost) *. c.cost }
      Card(..c, value: c.value *. ratio, cost:)
    }
  }
  Card(
    ..changed,
    name: attribute.name <> " " <> c.name,
    traits: scale_growth(c, changed.value),
  )
}

/// A growing card's growth scales with its value: a Broken Compress grows
/// to a fifth of a sound one.
fn scale_growth(c: Card, value: Float) -> List(card.Trait) {
  case c.value >. 0.0 {
    False -> c.traits
    True -> {
      let ratio = value /. c.value
      list.map(c.traits, fn(t) {
        case t {
          card.Grows(per_second:, cap:) ->
            card.Grows(per_second: per_second *. ratio, cap: cap *. ratio)
          other -> other
        }
      })
    }
  }
}

// WORTH AND IMPACT ------------------------------------------------------------

/// What a card is worth, in energy: its cost, scaled by how efficient it is
/// against its role's goal. Cards outside the efficiency band (counters,
/// launches, Smoke, Burn) count their cost.
pub fn card_worth(c: Card) -> Float {
  case efficiency.outside_band(c) {
    True -> c.cost
    False -> c.cost *. efficiency.rating(c) /. efficiency.goal(c)
  }
}

/// What a card is worth with an attribute, scaled by `strength` (a part's
/// Overclocked modifier). Cards outside the band have no goal to compare
/// with, so they count their base cost times the attribute's efficiency
/// change: value change over cost change.
pub fn worth(
  base: Card,
  attribute: Result(Attribute, Nil),
  strength: Float,
) -> Float {
  let applied = case attribute {
    Ok(a) -> apply(a, base)
    Error(Nil) -> base
  }
  case efficiency.outside_band(base) {
    True -> {
      let value_change = case value_matters(base) {
        True -> applied.value /. base.value
        False -> 1.0
      }
      base.cost *. strength *. value_change /. { applied.cost /. base.cost }
    }
    False -> card_worth(Card(..applied, value: applied.value *. strength))
  }
}

/// How much the attribute changes the card's worth (always positive): what
/// decides which attributes a part's name shows.
pub fn impact(attribute: Attribute, c: Card) -> Float {
  float.absolute_value(
    worth(c, Ok(attribute), 1.0) -. worth(c, Error(Nil), 1.0),
  )
}

/// Whether the attribute makes the card better.
pub fn is_good(attribute: Attribute, c: Card) -> Bool {
  worth(c, Ok(attribute), 1.0) >. worth(c, Error(Nil), 1.0)
}

/// Attribute names by total impact on these cards, biggest first.
pub fn ranked(attached: List(#(Attribute, Card))) -> List(String) {
  attached
  |> list.fold([], fn(acc, pair) {
    let #(a, c) = pair
    let add = impact(a, c)
    case list.key_find(acc, a.name) {
      Ok(total) -> list.key_set(acc, a.name, total +. add)
      Error(Nil) -> [#(a.name, add), ..acc]
    }
  })
  |> list.sort(fn(x, y) { float.compare(y.1, x.1) })
  |> list.map(fn(pair) { pair.0 })
}
