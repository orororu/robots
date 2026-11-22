//// A built robot, ready for a match. Robots are normally made with
//// `robots/construction/builder.build`, which checks weight, weapon mounts and batteries;
//// `new` skips those checks (useful in tests).

import gleam/float
import gleam/list
import robots/construction/part.{type Component}
import robots/rules/amount
import robots/rules/card.{type Card}

/// `hp`, `max_hp` and `energy_cap` are relative amounts: HP on the card value
/// scale, energy on the card cost scale.
pub type Robot {
  Robot(
    name: String,
    chassis: String,
    max_hp: Float,
    hp: Float,
    energy_cap: Float,
    components: List(Component),
  )
}

pub fn new(
  name: String,
  chassis chassis: String,
  max_hp max_hp: Float,
  energy_cap energy_cap: Float,
  components components: List(Component),
) -> Robot {
  Robot(name:, chassis:, max_hp:, hp: max_hp, energy_cap:, components:)
}

/// Every card from every part, with modifiers applied.
pub fn deck(robot: Robot) -> List(Card) {
  list.flat_map(robot.components, part.cards)
}

pub fn take_damage(robot: Robot, amount: Float) -> Robot {
  Robot(..robot, hp: amount.subtract(robot.hp, amount))
}

/// Restore HP, never above max HP.
pub fn repair(robot: Robot, amount: Float) -> Robot {
  Robot(..robot, hp: float.min(robot.max_hp, robot.hp +. amount))
}

pub fn is_destroyed(robot: Robot) -> Bool {
  amount.is_zero(robot.hp)
}
