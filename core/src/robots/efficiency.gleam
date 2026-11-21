//// Design rules for card strength: how much a card delivers per energy.
////
//// Two rules shape every card's target efficiency (`goal`):
////
//// - Bigger cards are more efficient, whatever their role (`cost_slope`).
//// - Defence and buffs beat attacks of the same cost, by a margin
////   that grows with cost (`role_bonus`). Cheap ones get no margin, so fast
////   small defences can't stall the round; big ones always outclass attacks
////   of the same cost, so no build is a glass cannon.
////
//// A card's real effect can still fall short of its rating (a defence's extra
//// value is wasted, a buff with no target does nothing), which the balance
//// report measures.

import gleam/float
import gleam/list
import robots/card.{type Card, All, Launch, One, Opponent, OpponentHp, Self}

pub type Role {
  Damage
  Weaken
  Strengthen
}

/// How many cards an `All(...)` card is expected to hit, for rating purposes.
pub const expected_all_targets = 2.0

/// Allowed deviation from a role's target rating.
pub const tolerance = 0.1

pub fn role(card: Card) -> Role {
  case card.target {
    OpponentHp | Launch(_) -> Damage
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
/// Defence and buffs beat attacks of the same cost, and the gap grows
/// with cost, so no attack is ever big enough to outclass defence.
pub fn role_bonus(role: Role) -> Float {
  case role {
    Damage -> 0.0
    Weaken -> 0.6
    Strengthen -> 0.4
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

/// `Once` cards are rated this much above their role's goal: they can be
/// played a single time per match.
pub const once_bonus = 1.6

/// Cards that only affect drones are rated this much higher: they do
/// nothing against a robot without drones.
pub const drone_only_bonus = 2.0

/// Target value-per-cost for this particular card. A launch card is rated by
/// its drone: launch plus strike cost, against the drone's full value.
pub fn goal(card: Card) -> Float {
  let base = goal_for(role(card), total_cost(card))
  let base = case card.has_trait(card, card.Once) {
    True -> base *. once_bonus
    False -> base
  }
  case drone_only(card) {
    True -> base *. drone_only_bonus
    False -> base
  }
}

fn total_cost(card: Card) -> Float {
  case card.target {
    Launch(drone) -> card.cost +. drone.cost
    _ -> card.cost
  }
}

fn drone_only(card: Card) -> Bool {
  case card.target {
    Opponent(One(tags))
    | Opponent(All(tags))
    | Self(One(tags))
    | Self(All(tags)) -> list.contains(tags, card.Drone)
    _ -> False
  }
}

/// The card's printed value per cost, counting `All` cards as hitting
/// `expected_all_targets` cards.
pub fn rating(card: Card) -> Float {
  case card.target, drone_only(card) {
    Launch(drone), _ -> full_value(drone) /. total_cost(card)
    // Few drones are up at once: rate as hitting one.
    _, True -> card.value /. card.cost
    Opponent(All(_)), False | Self(All(_)), False ->
      card.value *. expected_all_targets /. card.cost
    _, False -> card.value /. card.cost
  }
}

/// A drone's value once fully grown.
fn full_value(drone: Card) -> Float {
  case card.growth(drone) {
    Ok(#(_, cap)) -> cap
    Error(Nil) -> drone.value
  }
}

pub fn within_band(card: Card) -> Bool {
  let goal = goal(card)
  let r = rating(card)
  r >=. goal -. tolerance && r <=. goal +. tolerance
}

pub fn role_name(role: Role) -> String {
  case role {
    Damage -> "damage"
    Weaken -> "weaken"
    Strengthen -> "strengthen"
  }
}
