//// The enemy roster: named enemy types for each level (see docs/RUN.md).
////
//// A name always means the same build, so players learn what a "Rusty
//// brawler" does and pick a robot to counter it. Builds come from the build
//// tournament, climbing its ranking level by level: level 1 enemies score
//// about 20-30% there, level 2 about 40-50%, level 3 about 60%. Each level's
//// strong enemies are a step above its normal ones; bosses another step.
//// `gleam run -m enemies` checks each against the starter robots.

import gleam/list
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/construction/robot.{type Robot}
import robots/content/catalog as c

pub type Enemy {
  Enemy(
    name: String,
    /// What the player sees before the battle.
    description: String,
    chassis: Chassis,
    parts: List(Component),
  )
}

pub type Level {
  Level(level: Int, enemies: List(Enemy), strong: List(Enemy), boss: Enemy)
}

pub fn robot(enemy: Enemy) -> Robot {
  let assert Ok(bot) = builder.build(enemy.name, enemy.chassis, enemy.parts)
  bot
}

pub fn levels() -> List(Level) {
  [
    Level(
      level: 1,
      enemies: [rusty_brawler(), scrap_gunner(), rust_bucket(), grinder()],
      strong: [rocket_turtle(), firebug()],
      boss: foreman(),
    ),
    Level(
      level: 2,
      enemies: [rocket_turtle(), firebug(), beam_knight(), smoke_ripper()],
      strong: [iron_grinder(), twin_beam()],
      boss: warhead(),
    ),
    Level(
      level: 3,
      enemies: [iron_grinder(), twin_beam(), gunship(), flare()],
      strong: [bulwark(), hornet()],
      boss: siege_tank(),
    ),
  ]
}

/// The roster for a level. Levels past the last use the last one.
pub fn level(n: Int) -> Level {
  let all = levels()
  let assert Ok(last) = list.last(all)
  case list.find(all, fn(l) { l.level == n }) {
    Ok(l) -> l
    Error(Nil) -> last
  }
}

// LEVEL 1 ---------------------------------------------------------------------

pub fn rusty_brawler() -> Enemy {
  Enemy(
    "Rusty brawler",
    "A small, quick scrapper that throws punches and parries yours.",
    c.scout(),
    [
      c.fist(),
      c.buckler(),
      c.hydraulics(),
      c.reactor(),
      c.cell(),
      c.heavy_plating(),
      c.plating(),
    ],
  )
}

pub fn scrap_gunner() -> Enemy {
  Enemy(
    "Scrap gunner",
    "Two rattling machine guns behind a pair of bucklers.",
    c.frame(),
    [
      c.buckler(),
      c.buckler(),
      c.machine_gun(),
      c.machine_gun(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

pub fn rust_bucket() -> Enemy {
  Enemy(
    "Rust bucket",
    "A slow, heavily plated tank. One fist, a lot of parrying.",
    c.tank(),
    [
      c.fist(),
      c.buckler(),
      c.buckler(),
      c.buckler(),
      c.cell(),
      c.heavy_plating(),
      c.heavy_plating(),
      c.plating(),
    ],
  )
}

pub fn grinder() -> Enemy {
  Enemy(
    "Grinder",
    "A saw arm on a tough frame, shielded against bullets and shells.",
    c.brute(),
    [
      c.saw_arm(),
      c.kinetic_shield(),
      c.kinetic_shield(),
      c.buckler(),
      c.cell(),
      c.plating(),
    ],
  )
}

/// Level 1 boss.
pub fn foreman() -> Enemy {
  Enemy(
    "Foreman",
    "The scrapyard boss: a saw arm, kinetic and energy shields, heavy plating.",
    c.frame(),
    [
      c.saw_arm(),
      c.kinetic_shield(),
      c.deflector(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

// LEVEL 2 ---------------------------------------------------------------------

pub fn rocket_turtle() -> Enemy {
  Enemy(
    "Rocket turtle",
    "Hides behind deflectors and a buckler, then fires missiles.",
    c.frame(),
    [
      c.deflector(),
      c.deflector(),
      c.buckler(),
      c.missile_rack(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

pub fn firebug() -> Enemy {
  Enemy(
    "Firebug",
    "Sets your parried cards on fire, with a machine gun on the side.",
    c.brute(),
    [
      c.deflector(),
      c.buckler(),
      c.machine_gun(),
      c.flamethrower(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

pub fn beam_knight() -> Enemy {
  Enemy(
    "Beam knight",
    "A laser and plenty of shields against both bullets and beams.",
    c.brute(),
    [
      c.laser(),
      c.kinetic_shield(),
      c.deflector(),
      c.deflector(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

pub fn smoke_ripper() -> Enemy {
  Enemy(
    "Smoke ripper",
    "Closes in under smoke with an overcharged saw.",
    c.frame(),
    [
      c.saw_arm(),
      c.reactor(),
      c.reactor(),
      c.smoke_launcher(),
      c.cell(),
      c.plating(),
    ],
  )
}

/// Level 2 boss.
pub fn warhead() -> Enemy {
  Enemy(
    "Warhead",
    "A shielded missile carrier. Its missiles hit very hard.",
    c.brute(),
    [
      c.kinetic_shield(),
      c.buckler(),
      c.missile_rack(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

// LEVEL 3 ---------------------------------------------------------------------

pub fn iron_grinder() -> Enemy {
  Enemy(
    "Iron grinder",
    "A tank with a saw arm and double deflectors.",
    c.tank(),
    [
      c.saw_arm(),
      c.deflector(),
      c.deflector(),
      c.reactor(),
      c.cell(),
      c.heavy_plating(),
      c.heavy_plating(),
    ],
  )
}

pub fn twin_beam() -> Enemy {
  Enemy(
    "Twin beam",
    "Two lasers firing in turns, shielded against everything.",
    c.frame(),
    [
      c.laser(),
      c.laser(),
      c.kinetic_shield(),
      c.deflector(),
      c.cell(),
      c.plating(),
    ],
  )
}

pub fn gunship() -> Enemy {
  Enemy(
    "Gunship",
    "Machine gun and missiles behind two kinetic shields.",
    c.frame(),
    [
      c.kinetic_shield(),
      c.kinetic_shield(),
      c.machine_gun(),
      c.missile_rack(),
      c.cell(),
      c.plating(),
    ],
  )
}

pub fn flare() -> Enemy {
  Enemy(
    "Flare",
    "Laser and flamethrower, smoke against projectiles, guns against drones.",
    c.frame(),
    [
      c.laser(),
      c.point_defence(),
      c.smoke_launcher(),
      c.flamethrower(),
      c.cell(),
    ],
  )
}

pub fn bulwark() -> Enemy {
  Enemy("Bulwark", "A plated tank with a laser, hiding in smoke.", c.tank(), [
    c.laser(),
    c.deflector(),
    c.smoke_launcher(),
    c.smoke_launcher(),
    c.cell(),
    c.heavy_plating(),
    c.plating(),
  ])
}

pub fn hornet() -> Enemy {
  Enemy("Hornet", "A quick scout with two fists and a machine gun.", c.scout(), [
    c.fist(),
    c.fist(),
    c.targeting_computer(),
    c.machine_gun(),
    c.cell(),
    c.heavy_plating(),
    c.plating(),
  ])
}

/// Level 3 boss.
pub fn siege_tank() -> Enemy {
  Enemy(
    "Siege tank",
    "One huge cannon, aimed by a targeting computer. Shoots down drones.",
    c.tank(),
    [
      c.targeting_computer(),
      c.cannon(),
      c.point_defence(),
      c.cell(),
      c.heavy_plating(),
      c.plating(),
    ],
  )
}
