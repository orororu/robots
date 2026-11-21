import gleam/int
import gleam/list
import robots/card.{type Card}

/// A component installed on a robot. Every component contributes its cards
/// to the robot's deck.
pub type Component {
  Component(name: String, cards: List(Card))
}

pub type Robot {
  Robot(
    name: String,
    max_hp: Int,
    hp: Int,
    shield: Int,
    slots: Int,
    components: List(Component),
  )
}

pub type InstallError {
  NoFreeSlot
}

pub fn new(name: String, max_hp max_hp: Int, slots slots: Int) -> Robot {
  Robot(name:, max_hp:, hp: max_hp, shield: 0, slots:, components: [])
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

pub fn take_damage(robot: Robot, amount: Int) -> Robot {
  let absorbed = int.min(robot.shield, amount)
  let hp = int.max(0, robot.hp - { amount - absorbed })
  Robot(..robot, shield: robot.shield - absorbed, hp:)
}

pub fn add_shield(robot: Robot, amount: Int) -> Robot {
  Robot(..robot, shield: robot.shield + amount)
}

pub fn repair(robot: Robot, amount: Int) -> Robot {
  Robot(..robot, hp: int.min(robot.max_hp, robot.hp + amount))
}

pub fn is_destroyed(robot: Robot) -> Bool {
  robot.hp <= 0
}
