//// What a part is worth in credits, from what it does, what its cards cost
//// and how much it weighs. Used for shops and selling loot (see docs/RUN.md).
////
//// - **Cards:** each card counts its energy cost, scaled by how efficient it
////   is against its role's goal (`efficiency`). A card on its band counts its
////   cost; an Overclocked one counts 15% more. Cards outside the band
////   (narrow counters, launches, Smoke, Burn) count their cost, times the
////   part's modifier strength.
//// - **Armor:** each point of HP left counts 1, so wear lowers the price.
//// - **Batteries:** each point of energy cap counts 0.5.
//// - **Weight:** every unit of weight below `reference_weight` adds 10%,
////   every unit above takes 10% off (never below half).

import gleam/float
import gleam/list
import robots/construction/attribute
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/rules/card.{type Card}

/// Credits per unit of worth.
pub const credits = 10.0

/// A typical part's weight: no bonus, no discount.
pub const reference_weight = 3.0

pub const hp_worth = 1.0

pub const cap_worth = 0.5

pub const weight_step = 0.1

pub fn of(component: Component) -> Int {
  let worth =
    parts_cards_worth(component)
    +. part.remaining_hp(component)
    *. hp_worth
    +. part.energy_cap(component)
    *. cap_worth
  float.round(worth *. weight_factor(part.weight(component)) *. credits)
}

fn parts_cards_worth(component: Component) -> Float {
  let strength = part.strength(component)
  component.cards
  |> list.index_map(fn(c, i) {
    attribute.worth(c, list.key_find(component.attributes, i), strength)
  })
  |> float.sum
}

fn cards_worth(cards: List(Card)) -> Float {
  list.fold(cards, 0.0, fn(total, c) {
    total +. attribute.worth(c, Error(Nil), 1.0)
  })
}

fn weight_factor(weight: Float) -> Float {
  float.max(0.5, 1.0 +. weight_step *. { reference_weight -. weight })
}

// CHASSIS ---------------------------------------------------------------------

/// Credits per unit of weight a chassis can carry. A part is worth about 15
/// credits per unit of its weight, so a chassis' capacity is priced at
/// what it lets you fill.
pub const capacity_worth = 1.5

/// Chassis cards are rare: no part gives them (Sidestep, Jump, Ram...), so
/// they count this many times a part's card of the same worth.
pub const chassis_card_rarity = 3.0

/// Chassis are expensive: carrying capacity, base HP (less wear), and their
/// rare cards.
pub fn of_chassis(chassis: Chassis) -> Int {
  let worth =
    chassis.capacity
    *. capacity_worth
    +. builder.chassis_hp(chassis)
    *. hp_worth
    +. cards_worth(chassis.cards)
    *. chassis_card_rarity
  float.round(worth *. credits)
}
