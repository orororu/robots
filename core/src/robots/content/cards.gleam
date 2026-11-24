//// Every card in the game, one function each. Components
//// (`robots/content/components`) and chassis are built from these, so a new
//// weapon can be a new combination of existing cards.
////
//// Costs and values are relative to a base of 1.0 (see `robots/rules/scale`
//// for how they're shown). Every card must fit its efficiency band in
//// `robots/balance/efficiency` (bigger cards more efficient; defence and
//// buffs ahead of attacks of the same cost), unless noted. Values follow the
//// bands, so a variant 20% cheaper is about 30% weaker. A test checks every
//// card of `components.all()`; `gleam run -m balance` shows each card's goal.

import robots/rules/card.{
  type Card, type Scope, type Tag, All, Attack, Beam, Buff, Card, Defence, Drone,
  Energy, Explosive, Fire, Kinetic, Melee, Mobility, One, Opponent, OpponentHp,
  Range, Self,
}

// SHORTHANDS ------------------------------------------------------------------
// The tags `attack`, `defence` and `buff` are descriptive only: what a card
// does comes from its target.

/// Damages the opponent's HP.
pub fn attack(
  name: String,
  tags: List(Tag),
  cost: Float,
  value: Float,
) -> Card {
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
pub fn defence(
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
pub fn buff(
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

// BEAM (Laser) ----------------------------------------------------------------
// Energy attacks: a Deflector counters them. Beams, not range (projectile)
// attacks, so Smoke doesn't block them and a Targeting computer doesn't aim
// them.

pub fn pulse() -> Card {
  attack("Pulse", [Beam, Energy], 0.8, 0.72)
}

pub fn laser() -> Card {
  attack("Laser", [Beam, Energy], 1.0, 1.0)
}

pub fn focused_beam() -> Card {
  attack("Focused beam", [Beam, Energy], 1.3, 1.5)
}

pub fn overcharge() -> Card {
  attack("Overcharge", [Beam, Energy], 1.6, 2.1)
}

// MELEE (Saw arm, Fist) -------------------------------------------------------

pub fn nick() -> Card {
  attack("Nick", [Melee], 0.6, 0.48)
}

pub fn grind() -> Card {
  attack("Grind", [Melee], 0.8, 0.7)
}

pub fn rip() -> Card {
  attack("Rip", [Melee], 1.1, 1.15)
}

pub fn shred() -> Card {
  attack("Shred", [Melee], 1.5, 1.9)
}

pub fn jab() -> Card {
  attack("Jab", [Melee, Kinetic], 0.5, 0.38)
}

pub fn punch() -> Card {
  attack("Punch", [Melee, Kinetic], 0.6, 0.5)
}

pub fn haymaker() -> Card {
  attack("Haymaker", [Melee, Kinetic], 0.9, 0.86)
}

// RANGE (Cannon, Machine gun, Missile rack) -----------------------------------

pub fn quick_shot() -> Card {
  attack("Quick shot", [Range, Kinetic], 1.5, 1.9)
}

pub fn cannon_shot() -> Card {
  attack("Cannon shot", [Range, Kinetic], 2.0, 3.0)
}

pub fn heavy_shell() -> Card {
  attack("Heavy shell", [Range, Kinetic], 2.5, 4.4)
}

pub fn burst() -> Card {
  attack("Burst", [Range, Kinetic], 0.5, 0.4)
}

pub fn long_burst() -> Card {
  attack("Long burst", [Range, Kinetic], 0.8, 0.72)
}

/// Sprays the air: destroys a freshly launched drone, or halves a grown one.
/// Outside the band (a counter).
pub fn sweep() -> Card {
  defence("Sweep", [Range, Kinetic], 0.5, 1.5, One([Drone]))
}

/// Playable once per match and much stronger than a normal attack. At 15/30
/// the rack lost to a Laser in the same builds (58% vs 69%): two early
/// shots, then only weak rockets.
pub fn missile() -> Card {
  Card(..attack("Missile", [Range, Explosive], 1.8, 4.0), traits: [card.Once])
}

pub fn micro_rocket() -> Card {
  attack("Micro rocket", [Range, Explosive], 0.7, 0.6)
}

// DRONES (Drone bay) ----------------------------------------------------------

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

pub fn launch_drone() -> Card {
  Card(
    name: "Launch drone",
    // Not tagged Drone: only a launched drone soaks attacks.
    tags: [],
    cost: 1.4,
    value: 0.0,
    target: card.Launch(drone()),
    traits: [card.Once],
  )
}

// FIRE (Flamethrower) ---------------------------------------------------------

pub fn scorch() -> Card {
  attack("Scorch", [Fire], 0.6, 0.48)
}

pub fn flame() -> Card {
  attack("Flame", [Fire], 0.8, 0.7)
}

pub fn blaze() -> Card {
  attack("Blaze", [Fire], 1.3, 1.5)
}

/// A combo card. Once a defence has lowered an enemy card to 0, Ignite burns
/// it: the card leaves the match and Fire takes its slot. Without a zeroed
/// card on their table, Ignite does nothing.
pub fn ignite() -> Card {
  Card(
    name: "Ignite",
    tags: [Fire],
    cost: 0.4,
    value: 0.0,
    target: card.Burn(fire()),
    traits: [],
  )
}

/// What a burnt card leaves behind: it does nothing, costs as much to clear
/// as the burnt card (at least 5), and then leaves the match.
pub fn fire() -> Card {
  Card(
    name: "Fire",
    tags: [Fire],
    cost: 0.5,
    value: 0.0,
    target: card.NoEffect,
    traits: [card.Once],
  )
}

// COUNTERS (Smoke launcher, Point defence) ------------------------------------
// Outside the efficiency band; balanced by matchups (`counter_check`).

/// Lowers every range attack on *both* tables: it blinds you too.
pub fn smoke() -> Card {
  Card(
    name: "Smoke",
    tags: [Defence, Mobility],
    cost: 0.6,
    value: 1.6,
    target: card.Both(All([Attack, Range])),
    traits: [],
  )
}

/// Destroys a drone, even fully grown. Cheap (cost 3) so a dead card is
/// cheap to clear.
pub fn shoot_down() -> Card {
  defence("Shoot down", [Range], 0.3, 3.0, One([Drone]))
}

// WEAKEN (opponent's table) ---------------------------------------------------

/// Kinetic shield cards lower kinetic attacks only (Cannon, Machine gun,
/// Fist, Kick, Ram). Lasers pass through.
pub fn kinetic_flicker() -> Card {
  defence("Kinetic flicker", [Energy], 0.7, 0.68, One([Attack, Kinetic]))
}

pub fn kinetic_shield() -> Card {
  defence("Kinetic shield", [Energy], 1.0, 1.3, One([Attack, Kinetic]))
}

pub fn kinetic_bubble() -> Card {
  defence("Kinetic bubble", [Energy], 1.2, 0.91, All([Attack, Kinetic]))
}

/// Deflector cards lower energy attacks only (the Laser).
pub fn glance() -> Card {
  defence("Glance", [Energy], 0.6, 0.52, One([Attack, Energy]))
}

pub fn deflect() -> Card {
  defence("Deflect", [Energy], 0.8, 0.86, One([Attack, Energy]))
}

pub fn turn_aside() -> Card {
  defence("Turn aside", [Energy], 1.0, 1.3, One([Attack, Energy]))
}

/// Buckler cards parry melee attacks only.
pub fn quick_parry() -> Card {
  defence("Quick parry", [Melee], 0.6, 0.52, One([Attack, Melee]))
}

pub fn parry() -> Card {
  defence("Parry", [Melee], 0.8, 0.86, One([Attack, Melee]))
}

pub fn full_parry() -> Card {
  defence("Full parry", [Melee], 1.0, 1.3, One([Attack, Melee]))
}

/// Armor's card. Below the weaken band on purpose: armor-heavy decks fill up
/// with weak cards, so armor isn't free.
pub fn block() -> Card {
  defence("Block", [Kinetic], 0.5, 0.3, One([Attack]))
}

// STRENGTHEN (own table) ------------------------------------------------------

/// Targeting computer: aims range attacks.
pub fn quick_lock() -> Card {
  buff("Quick lock", [Range], 0.5, 0.38, One([Attack, Range]))
}

pub fn lock_on() -> Card {
  buff("Lock on", [Range], 0.6, 0.5, One([Attack, Range]))
}

pub fn full_lock() -> Card {
  buff("Full lock", [Range], 1.0, 1.2, One([Attack, Range]))
}

/// Hydraulics: strengthen melee attacks.
/// Ballistic computer: guns only (machine gun, cannon; not missiles or
/// lasers), with a Salvo that raises every gun on the table at once.
pub fn quick_sight() -> Card {
  buff("Quick sight", [Range], 0.5, 0.38, One([Attack, Range, Kinetic]))
}

pub fn sight() -> Card {
  buff("Sight", [Range], 0.6, 0.5, One([Attack, Range, Kinetic]))
}

/// Raises every gun attack: best with several machine guns.
pub fn salvo() -> Card {
  buff("Salvo", [Range], 0.9, 0.5, All([Attack, Range, Kinetic]))
}

pub fn twitch() -> Card {
  buff("Twitch", [Kinetic], 0.5, 0.38, One([Attack, Melee]))
}

pub fn pump() -> Card {
  buff("Pump", [Kinetic], 0.6, 0.5, One([Attack, Melee]))
}

pub fn surge() -> Card {
  buff("Surge", [Kinetic], 1.0, 1.2, One([Attack, Melee]))
}

// BATTERY CARDS ---------------------------------------------------------------
// Batteries store energy and some also bring buffs: capacitors for energy
// attacks (Laser, Drone), servo packs for melee.

/// Capacitors: raise energy attacks.
pub fn quick_charge() -> Card {
  buff("Quick charge", [Energy], 0.5, 0.38, One([Attack, Energy]))
}

pub fn charge() -> Card {
  buff("Charge", [Energy], 0.6, 0.5, One([Attack, Energy]))
}

/// Raises every energy attack, so its value per card is low.
pub fn full_charge() -> Card {
  buff("Full charge", [Energy], 0.9, 0.5, All([Attack, Energy]))
}

/// Servo packs: raise melee attacks.
pub fn quick_torque() -> Card {
  buff("Quick torque", [Kinetic], 0.5, 0.38, One([Attack, Melee]))
}

pub fn torque() -> Card {
  buff("Torque", [Kinetic], 0.6, 0.5, One([Attack, Melee]))
}

pub fn full_torque() -> Card {
  buff("Full torque", [Kinetic], 0.9, 0.5, All([Attack, Melee]))
}

// DEFENSIVE BUFFS -------------------------------------------------------------
// Raise your own defence cards, so they lower more when played.

/// Shield booster: any defence.
pub fn quick_boost() -> Card {
  buff("Quick boost", [Energy], 0.5, 0.38, One([Defence]))
}

pub fn boost() -> Card {
  buff("Boost", [Energy], 0.6, 0.5, One([Defence]))
}

pub fn full_boost() -> Card {
  buff("Full boost", [Energy], 1.0, 1.2, One([Defence]))
}

/// Gyroscope: movement defences (Sidestep, Dodge, Jump, Smoke).
pub fn balance() -> Card {
  buff("Balance", [Mobility], 0.5, 0.38, One([Defence, Mobility]))
}

pub fn steady() -> Card {
  buff("Steady", [Mobility], 0.6, 0.5, One([Defence, Mobility]))
}

pub fn gyro_lock() -> Card {
  buff("Gyro lock", [Mobility], 1.0, 1.2, One([Defence, Mobility]))
}

// CHASSIS ---------------------------------------------------------------------
// Mobility and identity. They come from no part, and can be strong: the
// chassis' price pays for them.

pub fn sidestep() -> Card {
  defence("Sidestep", [Mobility], 0.7, 0.68, One([Attack]))
}

pub fn kick() -> Card {
  attack("Kick", [Melee, Kinetic], 0.6, 0.48)
}

pub fn ram() -> Card {
  attack("Ram", [Melee, Kinetic], 0.8, 0.72)
}

pub fn brace() -> Card {
  defence("Brace", [Kinetic], 0.6, 0.52, One([Attack]))
}

pub fn jump() -> Card {
  defence("Jump", [Mobility], 0.8, 0.47, All([Attack, Melee]))
}

/// Mosquito moves: a flyer is hard to hit, each move against a different
/// kind of attack.
/// Rises out of reach of a melee blow.
pub fn hover() -> Card {
  defence("Hover", [Mobility], 0.5, 0.38, One([Attack, Melee]))
}

/// Rolls out of a shot's way.
pub fn barrel_roll() -> Card {
  defence("Barrel roll", [Mobility], 0.6, 0.52, One([Attack, Range]))
}

/// Weaves through every shot on the table, a little each.
pub fn zigzag() -> Card {
  defence("Zigzag", [Mobility], 0.8, 0.43, All([Attack, Range]))
}

pub fn dodge() -> Card {
  defence("Dodge", [Mobility], 0.7, 0.74, One([Attack]))
}
