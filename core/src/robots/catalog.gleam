//// Starter content. Plain data, so balancing is just editing numbers.
////
//// Costs and values are relative to a base of 1.0 (see `robots/scale` for how
//// they're shown). Every card must fit its efficiency band in
//// `robots/efficiency` (bigger cards more efficient; defence and buffs
//// ahead of attacks of the same cost). A test checks every card in
//// `components()`; `gleam run -m balance` shows each card's goal.

import robots/builder.{type Chassis, Chassis}
import robots/card.{
  type Card, type Scope, type Tag, All, Attack, Beam, Buff, Card, Defence, Drone,
  Energy, Explosive, Kinetic, Melee, Mobility, One, Opponent, OpponentHp, Range,
  Self,
}
import robots/part.{type Component}
import robots/robot.{type Robot}

// Shorthands. The tags `attack`, `defence` and `buff` are descriptive only:
// what a card does comes from its target.

/// Damages the opponent's HP.
fn attack(name: String, tags: List(Tag), cost: Float, value: Float) -> Card {
  Card(
    name:,
    tags: [Attack, ..tags],
    cost:,
    value:,
    target: OpponentHp,
    traits: [],
  )
}

/// Lowers cards on the opponent's table.
fn defence(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
  scope: Scope,
) -> Card {
  Card(
    name:,
    tags: [Defence, ..tags],
    cost:,
    value:,
    target: Opponent(scope),
    traits: [],
  )
}

/// Raises cards on your own table.
fn buff(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
  scope: Scope,
) -> Card {
  Card(
    name:,
    tags: [Buff, ..tags],
    cost:,
    value:,
    target: Self(scope),
    traits: [],
  )
}

/// Every component, for tests, the balance report and (later) the robot builder.
pub fn components() -> List(Component) {
  [
    laser(),
    saw_arm(),
    fist(),
    kinetic_shield(),
    deflector(),
    buckler(),
    targeting_computer(),
    hydraulics(),
    reactor(),
    cannon(),
    machine_gun(),
    missile_rack(),
    drone_bay(),
    point_defence(),
    smoke_launcher(),
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
// Every part has several variants of its base card: cheaper and weaker,
// pricier and stronger. Values follow the efficiency bands, so a variant 20%
// cheaper is about 30% weaker. That gives decks of 16-20 cards, so a robot
// can't just repeat its single best combo.

pub fn laser() -> Component {
  // The energy weapon: a Deflector counters it. A beam, not a range
  // (projectile) weapon, so Smoke doesn't block it and a Targeting computer
  // doesn't aim it.
  let laser = attack("Laser", [Beam, Energy], 1.0, 1.0)
  part.new("Laser", part.Weapon, 3.0, [
    attack("Pulse", [Beam, Energy], 0.8, 0.72),
    laser,
    laser,
    attack("Focused beam", [Beam, Energy], 1.3, 1.5),
    attack("Overcharge", [Beam, Energy], 1.6, 2.1),
  ])
}

pub fn saw_arm() -> Component {
  let grind = attack("Grind", [Melee], 0.8, 0.7)
  part.new("Saw arm", part.Weapon, 3.0, [
    attack("Nick", [Melee], 0.6, 0.48),
    grind,
    grind,
    attack("Rip", [Melee], 1.1, 1.15),
    attack("Shred", [Melee], 1.5, 1.9),
  ])
}

pub fn fist() -> Component {
  let punch = attack("Punch", [Melee, Kinetic], 0.6, 0.5)
  part.new("Fist", part.Weapon, 1.0, [
    attack("Jab", [Melee, Kinetic], 0.5, 0.38),
    punch,
    punch,
    attack("Haymaker", [Melee, Kinetic], 0.9, 0.86),
  ])
}

/// Heavy: needs a big mount (Tank) and a battery that holds 25.
pub fn cannon() -> Component {
  let shot = attack("Cannon shot", [Range, Kinetic], 2.0, 3.0)
  part.new("Cannon", part.Weapon, 6.0, [
    attack("Quick shot", [Range, Kinetic], 1.5, 1.9),
    shot,
    shot,
    attack("Heavy shell", [Range, Kinetic], 2.5, 4.4),
  ])
}

/// Light: fits small mounts, many cheap cards (Scout). Sweep sprays the
/// air: it destroys a freshly launched drone, or halves a grown one.
pub fn machine_gun() -> Component {
  let burst = attack("Burst", [Range, Kinetic], 0.5, 0.4)
  part.new("Machine gun", part.Weapon, 2.0, [
    burst,
    burst,
    burst,
    attack("Long burst", [Range, Kinetic], 0.8, 0.72),
    defence("Sweep", [Range, Kinetic], 0.5, 1.5, One([Drone])),
  ])
}

/// Two Missiles, each playable once per match and much stronger than a
/// normal attack, plus two ordinary rockets for the rest of the match.
pub fn missile_rack() -> Component {
  let missile =
    Card(..attack("Missile", [Range, Explosive], 1.5, 3.0), traits: [card.Once])
  let rocket = attack("Micro rocket", [Range, Explosive], 0.7, 0.6)
  part.new("Missile rack", part.Weapon, 3.0, [missile, missile, rocket, rocket])
}

/// The drone a Drone bay launches. It grows while it waits on the table
/// (15 to 30 over 15 s, at display scale). Play it to strike for its
/// current value. Meanwhile the opponent's attacks hit it instead of your
/// robot. A slower start (5, +0.5/s) got drones shot down before they
/// could strike.
pub fn drone() -> Card {
  Card(
    name: "Drone",
    tags: [Drone, Energy],
    // Nearly free to strike: the drone was paid for at launch.
    cost: 0.1,
    value: 1.5,
    target: OpponentHp,
    traits: [card.Once, card.Grows(per_second: 0.1, cap: 3.0)],
  )
}

/// Four drones, each launched once per match.
pub fn drone_bay() -> Component {
  let launch =
    Card(
      name: "Launch drone",
      // Not tagged Drone: only a launched drone soaks attacks.
      tags: [],
      cost: 1.4,
      value: 0.0,
      target: card.Launch(drone()),
      traits: [card.Once],
    )
  part.new("Drone bay", part.Weapon, 3.0, [launch, launch, launch, launch])
}

/// Smoke lowers every range attack on *both* tables: it blinds you too. A
/// specialist part for melee builds fighting range builds. Balanced by
/// matchups (`counter_check`), outside the efficiency band.
pub fn smoke_launcher() -> Component {
  let smoke =
    Card(
      name: "Smoke",
      tags: [Defence, Mobility],
      cost: 0.6,
      value: 1.6,
      target: card.Both(All([Attack, Range])),
      traits: [],
    )
  part.new("Smoke launcher", part.Defence, 2.0, [smoke, smoke, smoke, smoke])
}

/// Anti-drone, as a defence part: it takes weight, not a weapon mount.
/// Shoot down destroys a drone, even fully grown. A specialist part: dead
/// cards against builds without drones, the right pick against builds that
/// rely on them. Cheap (cost 3) so a dead card is cheap to clear. Checked
/// with `gleam run -m counter_check`; costlier versions, or two Intercepts
/// (against Missiles, which are fired before they can be intercepted),
/// were no better than a Kinetic shield even against drones.
/// (It used to be a Flak gun weapon: no one gave up a weapon mount for it,
/// and against drones it was no better than a Laser.)
pub fn point_defence() -> Component {
  let shoot_down = defence("Shoot down", [Range], 0.3, 3.0, One([Drone]))
  part.new("Point defence", part.Defence, 2.0, [
    shoot_down,
    shoot_down,
    shoot_down,
    shoot_down,
  ])
}

// WEAKEN (opponent's table) ---------------------------------------------------

/// Stops projectiles and blows: lowers kinetic attacks only (Cannon,
/// Machine gun, Fist, Kick, Ram). Lasers pass through; a Deflector stops
/// those.
pub fn kinetic_shield() -> Component {
  let shield =
    defence("Kinetic shield", [Energy], 1.0, 1.3, One([Attack, Kinetic]))
  part.new("Kinetic shield", part.Defence, 2.0, [
    defence("Kinetic flicker", [Energy], 0.7, 0.68, One([Attack, Kinetic])),
    shield,
    shield,
    defence("Kinetic bubble", [Energy], 1.2, 0.91, All([Attack, Kinetic])),
  ])
}

/// Bends energy beams away: lowers energy attacks only (the Laser). A light
/// specialist, like the Buckler for melee; the Kinetic shield is the
/// general, heavier defence.
pub fn deflector() -> Component {
  let deflect = defence("Deflect", [Energy], 0.8, 0.86, One([Attack, Energy]))
  part.new("Deflector", part.Defence, 1.0, [
    defence("Glance", [Energy], 0.6, 0.52, One([Attack, Energy])),
    deflect,
    deflect,
    defence("Turn aside", [Energy], 1.0, 1.3, One([Attack, Energy])),
  ])
}

/// A small hand shield: parries melee attacks only, so it's cheap and light
/// but useless against range builds.
pub fn buckler() -> Component {
  let parry = defence("Parry", [Melee], 0.8, 0.86, One([Attack, Melee]))
  part.new("Buckler", part.Defence, 1.0, [
    defence("Quick parry", [Melee], 0.6, 0.52, One([Attack, Melee])),
    parry,
    parry,
    defence("Full parry", [Melee], 1.0, 1.3, One([Attack, Melee])),
  ])
}

// STRENGTHEN (own table) ------------------------------------------------------

pub fn targeting_computer() -> Component {
  let lock_on = buff("Lock on", [Range], 0.6, 0.5, One([Attack, Range]))
  part.new("Targeting computer", part.Utility, 1.0, [
    buff("Quick lock", [Range], 0.5, 0.38, One([Attack, Range])),
    lock_on,
    lock_on,
    buff("Full lock", [Range], 1.0, 1.2, One([Attack, Range])),
  ])
}

pub fn hydraulics() -> Component {
  let pump = buff("Pump", [Kinetic], 0.6, 0.5, One([Attack, Melee]))
  part.new("Hydraulics", part.Utility, 1.0, [
    buff("Twitch", [Kinetic], 0.5, 0.38, One([Attack, Melee])),
    pump,
    pump,
    buff("Surge", [Kinetic], 1.0, 1.2, One([Attack, Melee])),
  ])
}

/// Overclock raises every attack, so its value per card is low.
pub fn reactor() -> Component {
  let overclock = buff("Overclock", [Energy], 0.9, 0.5, All([Attack]))
  part.new("Reactor", part.Utility, 2.0, [
    buff("Spike", [Energy], 0.6, 0.5, One([Attack])),
    overclock,
    overclock,
    buff("Overdrive", [Energy], 1.4, 1.09, All([Attack])),
  ])
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
// Armor adds HP and a weak Block card per 2 weight. Block is deliberately
// below its efficiency band: armor-heavy decks fill up with weak cards, so
// armor isn't free. Defence parts must beat armor per weight.

/// Below the weaken band on purpose (see above).
pub fn block() -> Card {
  defence("Block", [Kinetic], 0.5, 0.3, One([Attack]))
}

pub fn plating() -> Component {
  part.armor("Plating", 2.0, 2.5, [block()])
}

pub fn heavy_plating() -> Component {
  part.armor("Heavy plating", 4.0, 5.0, [block(), block()])
}

// CHASSIS ---------------------------------------------------------------------
// Each chassis brings its own cards: mobility and identity. Mobility lives
// here rather than in parts, and can be strong: the chassis' price pays for it.

/// All-rounder: two medium weapons, a sidestep and a kick.
pub fn frame() -> Chassis {
  let sidestep = defence("Sidestep", [Mobility], 0.7, 0.68, One([Attack]))
  let kick = attack("Kick", [Melee, Kinetic], 0.6, 0.48)
  Chassis("Frame", hp: 9.0, capacity: 12.0, weapon_mounts: [4.0, 4.0], cards: [
    sidestep,
    kick,
  ])
}

/// Tough, with one medium and one small weapon. Rams rather than dodges.
pub fn brute() -> Chassis {
  let ram = attack("Ram", [Melee, Kinetic], 0.8, 0.72)
  Chassis("Brute", hp: 7.0, capacity: 12.0, weapon_mounts: [4.0, 2.0], cards: [
    ram,
    ram,
  ])
}

/// One big gun and plenty of capacity. Slow: almost no mobility.
pub fn tank() -> Chassis {
  let brace = defence("Brace", [Kinetic], 0.6, 0.52, One([Attack]))
  Chassis("Tank", hp: 9.0, capacity: 16.0, weapon_mounts: [8.0], cards: [brace])
}

/// Fragile and light, four small weapons, and the best mobility: hard to hit.
pub fn scout() -> Chassis {
  let jump = defence("Jump", [Mobility], 0.8, 0.47, All([Attack, Melee]))
  let dodge = defence("Dodge", [Mobility], 0.7, 0.74, One([Attack]))
  Chassis(
    "Scout",
    hp: 8.0,
    capacity: 12.0,
    weapon_mounts: [2.0, 2.0, 2.0, 2.0],
    cards: [jump, jump, dodge, dodge],
  )
}

// ROBOTS ----------------------------------------------------------------------

/// The player's starter robot: a Laser, a Buckler against melee brawlers, and a
/// Reactor to boost attacks.
pub fn tinker() -> Robot {
  starter("Tinker", frame(), [
    laser(),
    buckler(),
    reactor(),
    big_battery(),
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
