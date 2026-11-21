//// Design rules for card strength: how much a card delivers per energy.
////
//// Defence, buffs and repair are rated *above* attacks on purpose: if pure
//// damage were the most efficient thing to spend energy on, every build would
//// be a glass cannon with the single best attack. A card's real effect can
//// still fall short of its rating (a defence's extra value is wasted, a buff
//// with no target does nothing), which the balance report measures.

import robots/card.{type Card, All, Hp, Opponent, Self}

pub type Role {
  Damage
  Repair
  Weaken
  Strengthen
}

/// How many cards an `All(...)` card is expected to hit, for rating purposes.
pub const expected_all_targets = 2.0

/// Allowed deviation from a role's target rating.
pub const tolerance = 0.1

pub fn role(card: Card) -> Role {
  case card.target {
    Opponent(Hp) -> Damage
    Self(Hp) -> Repair
    Opponent(_) -> Weaken
    Self(_) -> Strengthen
  }
}

/// Target value-per-cost for each role.
pub fn target(role: Role) -> Float {
  case role {
    Damage -> 1.0
    Repair -> 1.2
    Weaken -> 1.3
    Strengthen -> 1.3
  }
}

/// The card's printed value per cost, counting `All` cards as hitting
/// `expected_all_targets` cards.
pub fn rating(card: Card) -> Float {
  let hits = case card.target.scope {
    All(_) -> expected_all_targets
    _ -> 1.0
  }
  card.value *. hits /. card.cost
}

pub fn within_band(card: Card) -> Bool {
  let goal = target(role(card))
  let r = rating(card)
  r >=. goal -. tolerance && r <=. goal +. tolerance
}

pub fn role_name(role: Role) -> String {
  case role {
    Damage -> "damage"
    Repair -> "repair"
    Weaken -> "weaken"
    Strengthen -> "strengthen"
  }
}
