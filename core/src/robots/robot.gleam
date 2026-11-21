import gleam/list
import robots/amount
import robots/card.{type Card}

/// A component installed on a robot. Every component contributes its cards
/// to the robot's deck.
pub type Component {
  Component(name: String, cards: List(Card))
}

/// `hp` and `max_hp` are relative, on the same scale as card values.
pub type Robot {
  Robot(
    name: String,
    max_hp: Float,
    hp: Float,
    slots: Int,
    components: List(Component),
  )
}

pub type InstallError {
  NoFreeSlot
}

pub fn new(name: String, max_hp max_hp: Float, slots slots: Int) -> Robot {
  Robot(name:, max_hp:, hp: max_hp, slots:, components: [])
}

pub fn install(
  robot: Robot,
  component: Component,
) -> Result(Robot, InstallError) {
  case list.length(robot.components) < robot.slots {
    True ->
      Ok(Robot(..robot, components: list.append(robot.components, [component])))
    False -> Error(NoFreeSlot)
  }
}

pub fn deck(robot: Robot) -> List(Card) {
  list.flat_map(robot.components, fn(component) { component.cards })
}

pub fn take_damage(robot: Robot, amount: Float) -> Robot {
  Robot(..robot, hp: amount.subtract(robot.hp, amount))
}

pub fn is_destroyed(robot: Robot) -> Bool {
  amount.is_zero(robot.hp)
}
