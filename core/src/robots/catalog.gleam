//// Starter content. Plain data, so balancing is just editing numbers.

import gleam/list
import robots/card.{Card, Charge, Damage, Repair, Shield}
import robots/robot.{type Component, type Robot, Component}

pub fn blaster() -> Component {
  Component("Blaster", [
    Card("Zap", 2, [Damage(3)]),
    Card("Zap", 2, [Damage(3)]),
    Card("Blast", 5, [Damage(8)]),
  ])
}

pub fn plating() -> Component {
  Component("Plating", [
    Card("Brace", 2, [Shield(4)]),
    Card("Brace", 2, [Shield(4)]),
    Card("Bulwark", 4, [Shield(6), Damage(2)]),
  ])
}

pub fn repair_kit() -> Component {
  Component("Repair kit", [
    Card("Patch", 3, [Repair(5)]),
    Card("Patch", 3, [Repair(5)]),
  ])
}

pub fn capacitor() -> Component {
  Component("Capacitor", [
    Card("Surge", 1, [Charge(3.0)]),
    Card("Arc", 3, [Damage(4), Charge(1.0)]),
  ])
}

pub fn saw() -> Component {
  Component("Saw arm", [
    Card("Grind", 3, [Damage(5)]),
    Card("Grind", 3, [Damage(5)]),
    Card("Shred", 6, [Damage(11)]),
  ])
}

/// The player's starter robot.
pub fn tinker() -> Robot {
  build(robot.new("Tinker", max_hp: 40, slots: 4), [
    blaster(),
    plating(),
    repair_kit(),
    capacitor(),
  ])
}

/// The first AI opponent.
pub fn scrapper() -> Robot {
  build(robot.new("Scrapper", max_hp: 36, slots: 3), [
    saw(),
    blaster(),
    plating(),
  ])
}

fn build(base: Robot, components: List(Component)) -> Robot {
  list.fold(components, base, fn(bot, component) {
    let assert Ok(bot) = robot.install(bot, component)
    bot
  })
}
