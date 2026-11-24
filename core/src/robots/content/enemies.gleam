//// The enemy roster: named enemy types for each level (see docs/RUN.md).
////
//// Each roster entry is a build. When one is met in a run (`spawn`), its
//// cards get attributes by its **condition** (see `conditions`): early on,
//// enemies are rusty, every card Broken, Damaged or Weak, so fights cost
//// the player little HP; later they roll from the level's loot chart like
//// loot does. Its name is its roster name with its most impactful
//// attribute in front, e.g. "Broken rusty brawler". Builds come from the build
//// tournament, climbing its ranking level by level: level 1 enemies score
//// about 20-30% there, level 2 about 40-50%, level 3 about 60%. Each level's
//// strong enemies are a step above its normal ones; bosses another step.
//// `gleam run -m enemies` checks each against the starter robots.

import gleam/list
import gleam/string
import robots/construction/attribute
import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/construction/robot.{type Robot}
import robots/content/components as c
import robots/rules/rng.{type Seed}
import robots/run/loot

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

/// An enemy as met in a run: attributes rolled from the level's loot chart,
/// and named after its parts.
/// How worn down enemies are, from the most (step 0) up. At each step,
/// every card gets one of these attributes (weights). Steps past the list
/// roll attributes from the level's loot chart instead. The run's map picks
/// the step from the level and how strong the enemy is.
pub fn conditions() -> List(List(#(Int, attribute.Attribute))) {
  [
    [#(8, attribute.broken()), #(2, attribute.damaged())],
    [
      #(6, attribute.broken()),
      #(3, attribute.damaged()),
      #(1, attribute.weak()),
    ],
    [
      #(2, attribute.broken()),
      #(5, attribute.damaged()),
      #(3, attribute.weak()),
    ],
    [#(2, attribute.damaged()), #(4, attribute.weak()), #(4, attribute.worn())],
  ]
}

/// Meet an enemy: roll its card attributes for its condition `step` (see
/// `conditions`) on `level`, and name it after its parts.
pub fn spawn(
  enemy: Enemy,
  level: Int,
  step: Int,
  seed: Seed,
) -> #(Enemy, Seed) {
  let chart = loot.chart(level)
  let step = step + freshness(enemy)
  let condition = list.drop(conditions(), step) |> list.first
  let #(seed, parts) =
    list.map_fold(enemy.parts, seed, fn(seed, p) {
      let #(p, seed) = case condition {
        Ok(weights) -> loot.roll_card_attributes(p, 100, weights, seed)
        Error(Nil) -> loot.roll_attributes(chart, p, seed)
      }
      #(seed, p)
    })
  let spawned = Enemy(..enemy, parts:)
  #(Enemy(..spawned, name: name(spawned)), seed)
}

/// How many condition steps fresher than usual an enemy arrives. Level
/// monsters can't win anyway, so they come less worn, to bite harder.
pub const monster_freshness = 2

pub fn freshness(enemy: Enemy) -> Int {
  case list.contains(level_monsters(), enemy.name) {
    True -> monster_freshness
    False -> 0
  }
}

/// Weak robots that fill the levels: they never win, but take some HP.
pub fn level_monsters() -> List(String) {
  ["Junk fly", "Bottle fly", "Wasp"]
}

/// "Broken rusty brawler": the most impactful card attribute across all
/// parts, then the roster name. (Call it on a roster entry, not on an
/// already spawned enemy.)
pub fn name(enemy: Enemy) -> String {
  let attributes =
    enemy.parts
    |> list.flat_map(part.attached)
    |> attribute.ranked
    |> list.take(1)
  case attributes {
    [] -> enemy.name
    [top] ->
      capitalise(string.lowercase(top) <> " " <> string.lowercase(enemy.name))
    _ -> enemy.name
  }
}

fn capitalise(text: String) -> String {
  case string.pop_grapheme(text) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(Nil) -> text
  }
}

pub fn levels() -> List(Level) {
  [
    Level(
      level: 1,
      // The Dump: broken scrap robots, melee and rattling guns.
      enemies: [
        rusty_brawler(),
        scrap_gunner(),
        rust_bucket(),
        grinder(),
        junk_fly(),
        bottle_fly(),
      ],
      strong: [hubcap_knight(), incinerator(), foreman()],
      boss: compactor(),
    ),
    Level(
      level: 2,
      enemies: [
        rocket_turtle(),
        firebug(),
        beam_knight(),
        smoke_ripper(),
        wasp(),
        hailstorm(),
      ],
      strong: [iron_grinder(), twin_beam()],
      boss: warhead(),
    ),
    Level(
      level: 3,
      enemies: [iron_grinder(), twin_beam(), gunship(), flare()],
      strong: [bulwark(), hornet(), bastion()],
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
      c.servo_pack(),
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

/// Mosquitoes are level monsters, not duelists: they never win, but every
/// one takes a bite out of your HP.
pub fn junk_fly() -> Enemy {
  Enemy(
    "Junk fly",
    "A buzzing little flyer with a machine gun. Hard to hit, easy to break.",
    c.mosquito(),
    [
      c.machine_gun(),
      c.ballistic_computer(),
      c.gyroscope(),
      c.cell(),
      c.plating(),
    ],
  )
}

pub fn bottle_fly() -> Enemy {
  Enemy(
    "Bottle fly",
    "Darts in to punch, then hovers out of reach.",
    c.mosquito(),
    [c.fist(), c.hydraulics(), c.servo_pack(), c.plating()],
  )
}

/// The Dump's boss: a garbage compactor. Its Compresses grow slowly on the
/// table and hit very hard; shields against blows (Buckler, Kinetic shield)
/// keep knocking them back down. Its own shields stop bullets and beams.
pub fn compactor() -> Enemy {
  Enemy(
    "Compactor",
    "A garbage compactor. Its crusher plate closes slowly: knock it back with shields, or be flattened.",
    c.tank(),
    [
      c.crusher_plate(),
      c.kinetic_shield(),
      c.deflector(),
      c.cell(),
      c.heavy_plating(),
      c.plating(),
    ],
  )
}

/// Burns trash, and anything parried to nothing.
pub fn incinerator() -> Enemy {
  Enemy(
    "Incinerator",
    "Burns your parried cards, and punches the rest.",
    c.brute(),
    [
      c.flamethrower(),
      c.fist(),
      c.buckler(),
      c.deflector(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

/// A level 1 strong enemy (it was the boss before the Compactor).
pub fn foreman() -> Enemy {
  Enemy(
    "Foreman",
    "The dump's foreman: a saw arm, kinetic and energy shields, heavy plating.",
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
      c.big_servo_pack(),
      c.smoke_launcher(),
      c.plating(),
    ],
  )
}

pub fn wasp() -> Enemy {
  Enemy(
    "Wasp",
    "A mosquito with a sting: an aimed machine gun and boosted dodges.",
    c.mosquito(),
    [
      c.machine_gun(),
      c.ballistic_computer(),
      c.gyroscope(),
      c.shield_booster(),
      c.cell(),
    ],
  )
}

/// Many guns, then a Salvo that raises them all.
pub fn hailstorm() -> Enemy {
  Enemy(
    "Hailstorm",
    "Two machine guns and two ballistic computers: a Salvo, then a hail of bullets.",
    c.scout(),
    [
      c.machine_gun(),
      c.machine_gun(),
      c.ballistic_computer(),
      c.ballistic_computer(),
      c.cell(),
      c.heavy_plating(),
    ],
  )
}

/// Boosted parries: blocks melee builds cold, then saws.
pub fn hubcap_knight() -> Enemy {
  Enemy(
    "Hubcap knight",
    "Two hubcap bucklers, boosted to stop any blow, behind a saw and a fist.",
    c.brute(),
    [
      c.fist(),
      c.saw_arm(),
      c.shield_booster(),
      c.buckler(),
      c.buckler(),
      c.servo_pack(),
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
      c.servo_pack(),
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

/// Boosted shields and an aimed cannon.
pub fn bastion() -> Enemy {
  Enemy(
    "Bastion",
    "A cannon aimed by a ballistic computer, behind a boosted kinetic shield.",
    c.tank(),
    [
      c.cannon(),
      c.ballistic_computer(),
      c.shield_booster(),
      c.kinetic_shield(),
      c.battery(),
      c.plating(),
      c.plating(),
    ],
  )
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
