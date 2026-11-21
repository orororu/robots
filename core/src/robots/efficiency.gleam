//// Design rules for card strength: how much a card delivers per energy.
////
//// Two rules shape every card's target efficiency (`goal`):
////
//// - Bigger cards are more efficient, whatever their role (`cost_slope`).
//// - Defence, buffs and repair beat attacks of the same cost, by a margin
////   that grows with cost (`role_bonus`). Cheap ones get no margin, so fast
////   small defences can't stall the round; big ones always outclass attacks
////   of the same cost, so no build is a glass cannon.
////
//// A card's real effect can still fall short of its rating (a defence's extra
//// value is wasted, a buff with no target does nothing), which the balance
//// report measures.

import gleam/float
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

/// Every card gets this much more efficiency per unit of cost above the base
/// cost (1.0). Big cards are riskier (they wait longer on the table and cost
/// more to lose) and must be rewarded, or nobody plays them.
pub const cost_slope = 0.5

/// Below this cost no role gets a bonus over attacks, so cheap, fast defences
/// and buffs can't outperform attacks and stall the round.
pub const bonus_pivot_cost = 0.5

/// Extra efficiency per unit of cost above `bonus_pivot_cost`, by role.
/// Defence, buffs and repair beat attacks of the same cost, and the gap grows
/// with cost, so no attack is ever big enough to outclass defence.
pub fn role_bonus(role: Role) -> Float {
  case role {
    Damage -> 0.0
    Weaken -> 0.4
    Strengthen -> 0.4
    Repair -> 0.3
  }
}

/// Target value-per-cost for a card of this role and cost.
pub fn goal_for(role: Role, cost: Float) -> Float {
  1.0
  +. cost_slope
  *. { cost -. 1.0 }
  +. role_bonus(role)
  *. float.max(0.0, cost -. bonus_pivot_cost)
}

/// Target value-per-cost for this particular card.
pub fn goal(card: Card) -> Float {
  goal_for(role(card), card.cost)
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
  let goal = goal(card)
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
