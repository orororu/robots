//// The starter robots, built from `robots/content/components`.

import robots/construction/builder.{type Chassis}
import robots/construction/part.{type Component}
import robots/construction/robot.{type Robot}
import robots/content/components as c

/// The player's starter robot: a Laser, a Buckler against melee brawlers, and a
/// Big capacitor that stores energy and charges up the Laser.
pub fn tinker() -> Robot {
  starter("Tinker", c.frame(), tinker_parts())
}

pub fn tinker_parts() -> List(Component) {
  // With all HP halved and the Reactor gone, two Platings make up for the
  // lost buffs: 61% against the Scrapper (one Reinforced plating: 31%).
  [c.laser(), c.buckler(), c.big_capacitor(), c.plating(), c.plating()]
}

/// The first AI opponent: melee brawler.
pub fn scrapper() -> Robot {
  starter("Scrapper", c.brute(), [
    c.saw_arm(),
    c.fist(),
    c.hydraulics(),
    c.deflector(),
    c.battery(),
    c.plating(),
    c.plating(),
  ])
}

fn starter(name: String, chassis: Chassis, parts: List(Component)) -> Robot {
  let assert Ok(bot) = builder.build(name, chassis, parts)
  bot
}
