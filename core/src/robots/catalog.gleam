//// Starter content. Plain data, so balancing is just editing numbers.
////
//// Costs and values are relative to a base of 1.0 (see `robots/scale` for how
//// they're shown). Every card must fit its efficiency band in
//// `robots/efficiency` (bigger cards more efficient; defence and buffs
//// ahead of attacks of the same cost). A test checks every card in
//// `components()`; `gleam run -m balance` shows each card's goal.

import robots/builder.{type Chassis, Chassis}
import robots/card.{
  type Card, type Scope, type Tag, All, Attack, Beam, Buff, Card, Defence,
  Energy, Kinetic, Melee, Mobility, One, Opponent, OpponentHp, Range, Self,
}
import robots/part.{type Component}
import robots/robot.{type Robot}

// Shorthands. The tags `attack`, `defence` and `buff` are descriptive only:
// what a card does comes from its target.

/// Damages the opponent's HP.
fn attack(name: String, tags: List(Tag), cost: Float, value: Float) -> Card {
  Card(name:, tags: [Attack, ..tags], cost:, value:, target: OpponentHp)
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
    cannon(),
    machine_gun(),
    cell(),
    battery(),
    big_battery(),
    plating(),
    heavy_plating(),
  ]
}

pub fn chassis() -> List(Chassis) {
  [frame(), brute(), tank(), scout()]
}

// DAMAGE ----------------------------------------------------------------------

pub fn laser() -> Component {
  let laser = attack("Laser", [Range, Beam], 1.0, 1.0)
  part.new("Laser", part.Weapon, 3.0, [
    laser,
    laser,
    attack("Overcharge", [Range, Beam, Energy], 1.6, 2.1),
  ])
}

pub fn saw_arm() -> Component {
  let grind = attack("Grind", [Melee], 0.8, 0.7)
  part.new("Saw arm", part.Weapon, 3.0, [
    grind,
    grind,
    attack("Shred", [Melee], 1.5, 1.9),
  ])
}

pub fn fist() -> Component {
  let punch = attack("Punch", [Melee, Kinetic], 0.6, 0.5)
  part.new("Fist", part.Weapon, 1.0, [punch, punch])
}

/// Heavy: needs a big mount (Tank) and a battery that holds 20.
pub fn cannon() -> Component {
  let shot = attack("Cannon shot", [Range, Kinetic], 2.0, 3.0)
  part.new("Cannon", part.Weapon, 6.0, [shot, shot])
}

/// Light: fits small mounts, many cheap cards (Scout).
pub fn machine_gun() -> Component {
  let burst = attack("Burst", [Range, Kinetic], 0.5, 0.4)
  part.new("Machine gun", part.Weapon, 2.0, [burst, burst, burst])
}

// WEAKEN (opponent's table) ---------------------------------------------------

pub fn shield_emitter() -> Component {
  let shield = defence("Energy shield", [Energy], 1.0, 1.2, One([Attack]))
  part.new("Shield emitter", part.Defence, 2.0, [shield, shield])
}

pub fn deflector() -> Component {
  let deflect = defence("Deflect", [Kinetic], 0.7, 0.6, One([Attack]))
  part.new("Deflector", part.Defence, 1.0, [deflect, deflect])
}

/// Parry hits one melee attack, hard.
pub fn sword() -> Component {
  let parry = defence("Parry", [Melee], 0.8, 0.8, One([Attack, Melee]))
  part.new("Sword", part.Defence, 1.0, [parry, parry])
}

/// Jump hits every melee attack, so its value per card is low.
pub fn servo_legs() -> Component {
  let jump = defence("Jump", [Mobility], 0.8, 0.4, All([Attack, Melee]))
  part.new("Servo legs", part.Defence, 2.0, [jump, jump])
}

// STRENGTHEN (own table) ------------------------------------------------------

pub fn targeting_computer() -> Component {
  let lock_on = buff("Lock on", [Range], 0.6, 0.5, One([Attack, Range]))
  part.new("Targeting computer", part.Utility, 1.0, [lock_on, lock_on])
}

pub fn hydraulics() -> Component {
  let pump = buff("Pump", [Kinetic], 0.6, 0.5, One([Attack, Melee]))
  part.new("Hydraulics", part.Utility, 1.0, [pump, pump])
}

/// Overclock raises every attack, so its value per card is low.
pub fn reactor() -> Component {
  let overclock = buff("Overclock", [Energy], 0.9, 0.5, All([Attack]))
  part.new("Reactor", part.Utility, 2.0, [overclock, overclock])
}

// BATTERIES (energy storage) -------------------------------------------------

pub fn cell() -> Component {
  part.battery("Cell", 1.0, 3.0, [])
}

pub fn battery() -> Component {
  part.battery("Battery", 2.0, 5.0, [])
}

pub fn big_battery() -> Component {
  part.battery("Big battery", 4.0, 9.0, [])
}

// ARMOR (HP) ------------------------------------------------------------------
// Spare weight goes into armor, so its HP per weight (1.25) is the exchange
// rate for weight in general.

pub fn plating() -> Component {
  part.armor("Plating", 2.0, 2.5, [])
}

pub fn heavy_plating() -> Component {
  part.armor("Heavy plating", 4.0, 5.0, [])
}

// CHASSIS ---------------------------------------------------------------------

/// All-rounder: two medium weapons.
pub fn frame() -> Chassis {
  Chassis("Frame", hp: 8.5, capacity: 12.0, weapon_mounts: [4.0, 4.0])
}

/// Tough, with one medium and one small weapon.
pub fn brute() -> Chassis {
  Chassis("Brute", hp: 7.0, capacity: 12.0, weapon_mounts: [4.0, 2.0])
}

/// One big gun and plenty of capacity.
pub fn tank() -> Chassis {
  Chassis("Tank", hp: 9.0, capacity: 16.0, weapon_mounts: [8.0])
}

/// Fragile and light, but four small weapons.
pub fn scout() -> Chassis {
  Chassis("Scout", hp: 4.0, capacity: 10.0, weapon_mounts: [2.0, 2.0, 2.0, 2.0])
}

// ROBOTS ----------------------------------------------------------------------

/// The player's starter robot: ranged attacks, energy shields, Jump against melee.
pub fn tinker() -> Robot {
  starter("Tinker", frame(), [
    laser(),
    shield_emitter(),
    targeting_computer(),
    servo_legs(),
    battery(),
    plating(),
  ])
}

/// The first AI opponent: melee brawler.
pub fn scrapper() -> Robot {
  starter("Scrapper", brute(), [
    saw_arm(),
    fist(),
    hydraulics(),
    deflector(),
    battery(),
    plating(),
    plating(),
  ])
}

fn starter(name: String, chassis: Chassis, parts: List(Component)) -> Robot {
  let assert Ok(bot) = builder.build(name, chassis, parts)
  bot
}
