//// Starter content. Plain data, so balancing is just editing numbers.
////
//// Costs and values are relative to a base of 1.0 (see `robots/scale` for
//// how they're shown). Rule of thumb: value ≈ cost for single-target cards;
//// multi-target cards (Jump) get a lower value for their cost.

import gleam/list
import robots/card.{
  type Card, type Reach, type Tag, All, Attack, Beam, Buff, Card, Defence,
  Energy, Kinetic, Melee, Mobility, NoReach, One, Range,
}
import robots/robot.{type Component, type Robot, Component}

fn attack(name: String, tags: List(Tag), cost: Float, value: Float) -> Card {
  Card(name:, tags: [Attack, ..tags], cost:, value:, reach: NoReach)
}

fn defence(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
  reach: Reach,
) -> Card {
  Card(name:, tags: [Defence, ..tags], cost:, value:, reach:)
}

fn buff(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
  reach: Reach,
) -> Card {
  Card(name:, tags: [Buff, ..tags], cost:, value:, reach:)
}

// ATTACK COMPONENTS -----------------------------------------------------------

pub fn laser() -> Component {
  let laser = attack("Laser", [Range, Beam], 1.0, 1.0)
  Component("Laser", [
    laser,
    laser,
    attack("Overcharge", [Range, Beam, Energy], 1.6, 1.8),
  ])
}

pub fn saw_arm() -> Component {
  let grind = attack("Grind", [Melee], 0.8, 0.8)
  Component("Saw arm", [grind, grind, attack("Shred", [Melee], 1.5, 1.7)])
}

pub fn fist() -> Component {
  let punch = attack("Punch", [Melee, Kinetic], 0.5, 0.5)
  Component("Fist", [punch, punch])
}

// DEFENCE COMPONENTS ----------------------------------------------------------

pub fn shield_emitter() -> Component {
  let shield =
    defence("Energy shield", [Energy], 0.8, 0.7, One(matching: [Attack]))
  Component("Shield emitter", [shield, shield])
}

/// Jump hits every melee attack, so its value is low.
pub fn servo_legs() -> Component {
  let jump =
    defence("Jump", [Mobility], 0.8, 0.3, All(matching: [Attack, Melee]))
  Component("Servo legs", [jump, jump])
}

/// Parry hits one melee attack, hard.
pub fn sword() -> Component {
  let parry =
    defence("Parry", [Melee], 0.6, 0.8, One(matching: [Attack, Melee]))
  Component("Sword", [parry, parry])
}

pub fn deflector() -> Component {
  let deflect = defence("Deflect", [Kinetic], 0.7, 0.6, One(matching: [Attack]))
  Component("Deflector", [deflect, deflect])
}

// BUFF COMPONENTS -------------------------------------------------------------

pub fn targeting_computer() -> Component {
  let lock_on =
    buff("Lock on", [Range], 0.5, 0.4, One(matching: [Attack, Range]))
  Component("Targeting computer", [lock_on, lock_on])
}

pub fn hydraulics() -> Component {
  let pump = buff("Pump", [Kinetic], 0.5, 0.4, One(matching: [Attack, Melee]))
  Component("Hydraulics", [pump, pump])
}

// ROBOTS ----------------------------------------------------------------------

/// The player's starter robot: ranged attacks, with shields and Jump against melee.
pub fn tinker() -> Robot {
  build(robot.new("Tinker", max_hp: 12.0, slots: 4), [
    laser(),
    shield_emitter(),
    targeting_computer(),
    servo_legs(),
  ])
}

/// The first AI opponent: melee brawler.
pub fn scrapper() -> Robot {
  build(robot.new("Scrapper", max_hp: 12.0, slots: 4), [
    saw_arm(),
    fist(),
    hydraulics(),
    deflector(),
  ])
}

fn build(base: Robot, components: List(Component)) -> Robot {
  list.fold(components, base, fn(bot, component) {
    let assert Ok(bot) = robot.install(bot, component)
    bot
  })
}
