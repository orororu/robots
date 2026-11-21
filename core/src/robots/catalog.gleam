//// Starter content. Plain data, so balancing is just editing numbers.
////
//// Costs and values are relative to a base of 1.0 (see `robots/scale` for how
//// they're shown). Every card must fit its efficiency band in
//// `robots/efficiency` (bigger cards more efficient; defence, buffs and repair
//// ahead of attacks of the same cost). A test checks every card in
//// `components()`; `gleam run -m balance` shows each card's goal.

import gleam/list
import robots/card.{
  type Card, type Scope, type Tag, All, Attack, Beam, Buff, Card, Defence,
  Energy, Hp, Kinetic, Melee, Mobility, One, Opponent, Range, Self,
}
import robots/robot.{type Component, type Robot, Component}

// Shorthands. The tags `attack`, `defence` and `buff` are descriptive only:
// what a card does comes from its target.

/// Damages the opponent's HP.
fn attack(name: String, tags: List(Tag), cost: Float, value: Float) -> Card {
  Card(name:, tags: [Attack, ..tags], cost:, value:, target: Opponent(Hp))
}

/// Lowers cards on the opponent's table.
fn defence(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
  scope: Scope,
) -> Card {
  Card(name:, tags: [Defence, ..tags], cost:, value:, target: Opponent(scope))
}

/// Raises cards on your own table.
fn buff(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
  scope: Scope,
) -> Card {
  Card(name:, tags: [Buff, ..tags], cost:, value:, target: Self(scope))
}

/// Restores your own HP.
fn repair(name: String, tags: List(Tag), cost: Float, value: Float) -> Card {
  Card(name:, tags: [Buff, ..tags], cost:, value:, target: Self(Hp))
}

/// Every component, for tests, the balance report and (later) the robot builder.
pub fn components() -> List(Component) {
  [
    laser(),
    saw_arm(),
    fist(),
    shield_emitter(),
    deflector(),
    sword(),
    servo_legs(),
    targeting_computer(),
    hydraulics(),
    reactor(),
    repair_kit(),
  ]
}

// DAMAGE ----------------------------------------------------------------------

pub fn laser() -> Component {
  let laser = attack("Laser", [Range, Beam], 1.0, 1.0)
  Component("Laser", [
    laser,
    laser,
    attack("Overcharge", [Range, Beam, Energy], 1.6, 2.1),
  ])
}

pub fn saw_arm() -> Component {
  let grind = attack("Grind", [Melee], 0.8, 0.7)
  Component("Saw arm", [grind, grind, attack("Shred", [Melee], 1.5, 1.9)])
}

pub fn fist() -> Component {
  let punch = attack("Punch", [Melee, Kinetic], 0.6, 0.5)
  Component("Fist", [punch, punch])
}

// WEAKEN (opponent's table) ---------------------------------------------------

pub fn shield_emitter() -> Component {
  let shield = defence("Energy shield", [Energy], 1.0, 1.2, One([Attack]))
  Component("Shield emitter", [shield, shield])
}

pub fn deflector() -> Component {
  let deflect = defence("Deflect", [Kinetic], 0.7, 0.6, One([Attack]))
  Component("Deflector", [deflect, deflect])
}

/// Parry hits one melee attack, hard.
pub fn sword() -> Component {
  let parry = defence("Parry", [Melee], 0.8, 0.8, One([Attack, Melee]))
  Component("Sword", [parry, parry])
}

/// Jump hits every melee attack, so its value per card is low.
pub fn servo_legs() -> Component {
  let jump = defence("Jump", [Mobility], 0.8, 0.4, All([Attack, Melee]))
  Component("Servo legs", [jump, jump])
}

// STRENGTHEN (own table) ------------------------------------------------------

pub fn targeting_computer() -> Component {
  let lock_on = buff("Lock on", [Range], 0.6, 0.5, One([Attack, Range]))
  Component("Targeting computer", [lock_on, lock_on])
}

pub fn hydraulics() -> Component {
  let pump = buff("Pump", [Kinetic], 0.6, 0.5, One([Attack, Melee]))
  Component("Hydraulics", [pump, pump])
}

/// Overclock raises every attack, so its value per card is low.
pub fn reactor() -> Component {
  let overclock = buff("Overclock", [Energy], 0.9, 0.5, All([Attack]))
  Component("Reactor", [overclock, overclock])
}

// REPAIR ----------------------------------------------------------------------

pub fn repair_kit() -> Component {
  let patch = repair("Patch", [], 1.0, 1.2)
  Component("Repair kit", [patch, patch])
}

// ROBOTS ----------------------------------------------------------------------

/// The player's starter robot: ranged attacks, energy shields, Jump against melee.
pub fn tinker() -> Robot {
  build(robot.new("Tinker", max_hp: 11.0, slots: 4), [
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
