//// Every part and chassis: which cards each brings (from
//// `robots/content/cards`), its weight, HP and energy. Plain data, so
//// balancing is just editing numbers.

import robots/construction/builder.{type Chassis, Chassis}
import robots/construction/part.{type Component}
import robots/content/cards

/// Every component, for tests, the balance report, loot and the builder.
pub fn all() -> List(Component) {
  [
    laser(),
    saw_arm(),
    fist(),
    kinetic_shield(),
    deflector(),
    buckler(),
    targeting_computer(),
    hydraulics(),
    ballistic_computer(),
    shield_booster(),
    gyroscope(),
    cannon(),
    machine_gun(),
    missile_rack(),
    drone_bay(),
    point_defence(),
    smoke_launcher(),
    flamethrower(),
    railgun(),
    arc_welder(),
    needle_gun(),
    cell(),
    battery(),
    big_battery(),
    capacitor(),
    big_capacitor(),
    servo_pack(),
    big_servo_pack(),
    plating(),
    heavy_plating(),
  ]
}

pub fn chassis() -> List(Chassis) {
  [frame(), brute(), tank(), scout(), mosquito()]
}

// DAMAGE ----------------------------------------------------------------------
// Every part has several variants of its base card: cheaper and weaker,
// pricier and stronger. That gives decks of 16-20 cards, so a robot can't
// just repeat its single best combo.

pub fn laser() -> Component {
  part.new("Laser", part.Weapon, 3.0, [
    cards.pulse(),
    cards.laser(),
    cards.laser(),
    cards.focused_beam(),
    cards.overcharge(),
  ])
}

pub fn saw_arm() -> Component {
  part.new("Saw arm", part.Weapon, 3.0, [
    cards.nick(),
    cards.grind(),
    cards.grind(),
    cards.rip(),
    cards.shred(),
  ])
}

pub fn fist() -> Component {
  part.new("Fist", part.Weapon, 1.0, [
    cards.jab(),
    cards.punch(),
    cards.punch(),
    cards.haymaker(),
  ])
}

/// An energy cannon for a Frame's mount: two Rail shots that charge on the
/// table, and two Pulses to keep firing meanwhile.
pub fn railgun() -> Component {
  part.new("Railgun", part.Weapon, 4.0, [
    cards.pulse(),
    cards.pulse(),
    cards.rail_shot(),
    cards.rail_shot(),
  ])
}

/// Light melee that's also energy: every melee and energy buff raises it.
pub fn arc_welder() -> Component {
  part.new("Arc welder", part.Weapon, 1.5, [
    cards.spark(),
    cards.arc(),
    cards.arc(),
    cards.weld(),
  ])
}

/// The lightest gun: many cheap shots for gun buffs to land on.
pub fn needle_gun() -> Component {
  part.new("Needle gun", part.Weapon, 1.5, [
    cards.needle(),
    cards.needle(),
    cards.needle(),
    cards.volley(),
  ])
}

/// Heavy: needs a big mount (Tank) and a battery that holds 25.
pub fn cannon() -> Component {
  part.new("Cannon", part.Weapon, 6.0, [
    cards.quick_shot(),
    cards.cannon_shot(),
    cards.cannon_shot(),
    cards.heavy_shell(),
  ])
}

/// Light: fits small mounts, many cheap cards (Scout), and a Sweep against
/// drones.
pub fn machine_gun() -> Component {
  part.new("Machine gun", part.Weapon, 2.0, [
    cards.burst(),
    cards.burst(),
    cards.burst(),
    cards.long_burst(),
    cards.sweep(),
  ])
}

/// Two Missiles, each playable once per match, plus two ordinary rockets
/// for the rest of the match.
pub fn missile_rack() -> Component {
  part.new("Missile rack", part.Weapon, 3.0, [
    cards.missile(),
    cards.missile(),
    cards.micro_rocket(),
    cards.micro_rocket(),
  ])
}

/// Four drones, each launched once per match.
pub fn drone_bay() -> Component {
  let launch = cards.launch_drone()
  part.new("Drone bay", part.Weapon, 3.0, [launch, launch, launch, launch])
}

/// Flames, and Ignite to burn zeroed cards. Six cards, one more than usual:
/// with 2 Ignites (often dead) and 3 attacks it was rarely picked
/// (tournament lift 0.1-0.2).
pub fn flamethrower() -> Component {
  part.new("Flamethrower", part.Weapon, 3.0, [
    cards.scorch(),
    cards.flame(),
    cards.flame(),
    cards.blaze(),
    cards.ignite(),
    cards.ignite(),
  ])
}

/// The Compactor's weapon (boss only: not in `all`, so it never drops and
/// the tournament doesn't build with it). Two slowly growing Compresses and
/// two Shoves to keep the table moving. Heavy: needs a Tank's mount.
pub fn crusher_plate() -> Component {
  part.new("Crusher plate", part.Weapon, 5.0, [
    cards.compress(),
    cards.compress(),
    cards.shove(),
    cards.shove(),
  ])
}

/// A specialist part for melee builds fighting range builds: Smoke blinds
/// both sides' range attacks.
pub fn smoke_launcher() -> Component {
  let smoke = cards.smoke()
  part.new("Smoke launcher", part.Defence, 2.0, [smoke, smoke, smoke, smoke])
}

/// Anti-drone, as a defence part: it takes weight, not a weapon mount. A
/// specialist part: dead cards against builds without drones, the right pick
/// against builds that rely on them. Checked with `gleam run -m
/// counter_check`; costlier versions, or two Intercepts (against Missiles,
/// which are fired before they can be intercepted), were no better than a
/// Kinetic shield even against drones.
/// (It used to be a Flak gun weapon: no one gave up a weapon mount for it,
/// and against drones it was no better than a Laser.)
pub fn point_defence() -> Component {
  let shoot_down = cards.shoot_down()
  part.new("Point defence", part.Defence, 2.0, [
    shoot_down,
    shoot_down,
    shoot_down,
    shoot_down,
  ])
}

// WEAKEN (opponent's table) ---------------------------------------------------

/// Stops projectiles and blows: lowers kinetic attacks only. Lasers pass
/// through; a Deflector stops those.
pub fn kinetic_shield() -> Component {
  part.new("Kinetic shield", part.Defence, 2.0, [
    cards.kinetic_flicker(),
    cards.kinetic_shield(),
    cards.kinetic_shield(),
    cards.kinetic_bubble(),
  ])
}

/// Bends energy beams away. A light specialist, like the Buckler for melee;
/// the Kinetic shield is the general, heavier defence.
pub fn deflector() -> Component {
  part.new("Deflector", part.Defence, 1.0, [
    cards.glance(),
    cards.deflect(),
    cards.deflect(),
    cards.turn_aside(),
  ])
}

/// A small hand shield: parries melee attacks only, so it's cheap and light
/// but useless against range builds.
pub fn buckler() -> Component {
  part.new("Buckler", part.Defence, 1.0, [
    cards.quick_parry(),
    cards.parry(),
    cards.parry(),
    cards.full_parry(),
  ])
}

// STRENGTHEN (own table) ------------------------------------------------------

pub fn targeting_computer() -> Component {
  part.new("Targeting computer", part.Utility, 1.0, [
    cards.quick_lock(),
    cards.lock_on(),
    cards.lock_on(),
    cards.full_lock(),
  ])
}

/// For gun builds: raises machine gun and cannon attacks. Narrower than
/// the Targeting computer (no missiles), but its Salvo raises every gun.
pub fn ballistic_computer() -> Component {
  part.new("Ballistic computer", part.Utility, 1.0, [
    cards.quick_sight(),
    cards.sight(),
    cards.sight(),
    cards.salvo(),
  ])
}

pub fn hydraulics() -> Component {
  part.new("Hydraulics", part.Utility, 1.0, [
    cards.twitch(),
    cards.pump(),
    cards.pump(),
    cards.surge(),
  ])
}

/// Raises your own defence cards: any of them.
pub fn shield_booster() -> Component {
  part.new("Shield booster", part.Utility, 1.0, [
    cards.quick_boost(),
    cards.boost(),
    cards.boost(),
    cards.full_boost(),
  ])
}

/// Raises your own movement defences: the chassis' dodges (and Smoke).
/// Dead weight on a chassis without them (Brute, Tank).
pub fn gyroscope() -> Component {
  part.new("Gyroscope", part.Utility, 1.0, [
    cards.balance(),
    cards.steady(),
    cards.steady(),
    cards.gyro_lock(),
  ])
}

// BATTERIES (energy storage, some with buffs) -------------------------------------------------

pub fn cell() -> Component {
  part.battery("Cell", 1.0, 3.0, [])
}

pub fn battery() -> Component {
  part.battery("Battery", 2.0, 5.0, [])
}

pub fn big_battery() -> Component {
  part.battery("Big battery", 4.0, 9.0, [])
}

/// Energy batteries: store as much as a Battery, and raise energy attacks
/// (Laser, Drone). A little heavier for their cards.
pub fn capacitor() -> Component {
  part.battery("Capacitor", 1.5, 5.0, [cards.quick_charge(), cards.charge()])
}

pub fn big_capacitor() -> Component {
  part.battery("Big capacitor", 3.0, 9.0, [
    cards.quick_charge(),
    cards.charge(),
    cards.charge(),
    cards.full_charge(),
  ])
}

/// Melee batteries: raise melee attacks.
pub fn servo_pack() -> Component {
  part.battery("Servo pack", 1.5, 5.0, [cards.quick_torque(), cards.torque()])
}

pub fn big_servo_pack() -> Component {
  part.battery("Big servo pack", 3.0, 9.0, [
    cards.quick_torque(),
    cards.torque(),
    cards.torque(),
    cards.full_torque(),
  ])
}

// ARMOR (HP) ----
// HP was halved for everyone (chassis and armor) to make battles about
// twice as quick; card values stayed.--------------------------------------------------------------
// Armor adds HP and a weak Block card per 2 weight. Defence parts must beat
// armor per weight.

pub fn plating() -> Component {
  part.armor("Plating", 2.0, 1.25, [cards.block()])
}

pub fn heavy_plating() -> Component {
  part.armor("Heavy plating", 4.0, 2.5, [cards.block(), cards.block()])
}

// CHASSIS ---------------------------------------------------------------------
// Each chassis brings its own cards: mobility and identity.

/// All-rounder: two medium weapons, a sidestep and a kick.
pub fn frame() -> Chassis {
  Chassis(
    "Frame",
    hp: 4.5,
    capacity: 12.0,
    weapon_mounts: [4.0, 4.0],
    cards: [cards.sidestep(), cards.kick()],
    wear: 0.0,
  )
}

/// Tough, with one medium and one small weapon. Rams rather than dodges.
pub fn brute() -> Chassis {
  Chassis(
    "Brute",
    hp: 3.5,
    capacity: 12.0,
    weapon_mounts: [4.0, 2.0],
    cards: [cards.ram(), cards.ram()],
    wear: 0.0,
  )
}

/// One big gun and plenty of capacity. Slow: almost no mobility.
pub fn tank() -> Chassis {
  Chassis(
    "Tank",
    hp: 4.5,
    capacity: 16.0,
    weapon_mounts: [8.0],
    cards: [cards.brace()],
    wear: 0.0,
  )
}

/// Fragile and light, four small weapons, and the best mobility: hard to hit.
pub fn scout() -> Chassis {
  Chassis(
    "Scout",
    hp: 4.0,
    capacity: 12.0,
    weapon_mounts: [2.0, 2.0, 2.0, 2.0],
    cards: [cards.jump(), cards.jump(), cards.dodge(), cards.dodge()],
    wear: 0.0,
  )
}

/// A tiny flyer: one small weapon, very little HP and capacity, and a
/// different dodge for every kind of attack. Lasers are its weakness: only
/// Dodge works against them.
pub fn mosquito() -> Chassis {
  Chassis(
    "Mosquito",
    hp: 2.5,
    capacity: 7.0,
    weapon_mounts: [2.0],
    cards: [
      cards.hover(),
      cards.barrel_roll(),
      cards.barrel_roll(),
      cards.zigzag(),
      cards.dodge(),
      cards.dodge(),
    ],
    wear: 0.0,
  )
}
