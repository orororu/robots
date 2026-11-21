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
import robots/card.{
  type Card, All, Both, Launch, One, Opponent, OpponentHp, Self,
}

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
    Opponent(_) | Both(_) -> Weaken
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

/// Target value-per-cost for this particular card. A launch card is rated by
/// its drone: launch plus strike cost, against the drone's full value.
pub fn goal(card: Card) -> Float {
  let base = goal_for(role(card), total_cost(card))
  let base = case card.has_trait(card, card.Once) {
    True -> base *. once_bonus
    False -> base
  }
  base
}

fn total_cost(card: Card) -> Float {
  case card.target {
    Launch(drone) -> card.cost +. drone.cost
    _ -> card.cost
  }
}

/// Cards balanced by matchups and the tournament instead of the band:
/// narrow counters (below), and drone launches, whose drones are worth more
/// than their strike because they also soak the opponent's attacks, and
/// Smoke, which hurts both sides.
pub fn outside_band(card: Card) -> Bool {
  case card.target {
    // Smoke also lowers your own cards: its worth depends on the matchup.
    Launch(_) | Both(_) -> True
    _ -> narrow_counter(card)
  }
}

/// Narrow counters only affect drones (or explosive attacks): dead cards
/// against everything else, decisive against their targets. They're balanced
/// by matchups (a counter part should beat a general one against its
/// targets, and lose elsewhere), not by the efficiency band.
pub fn narrow_counter(card: Card) -> Bool {
  case card.target {
    Opponent(One(tags))
    | Opponent(All(tags))
    | Self(One(tags))
    | Self(All(tags)) ->
      list.contains(tags, card.Drone) || list.contains(tags, card.Explosive)
    _ -> False
  }
}

/// The card's printed value per cost, counting `All` cards as hitting
/// `expected_all_targets` cards.
pub fn rating(card: Card) -> Float {
  case card.target {
    Launch(drone) -> full_value(drone) /. total_cost(card)
    Opponent(All(_)) | Self(All(_)) ->
      card.value *. expected_all_targets /. card.cost
    _ -> card.value /. card.cost
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
