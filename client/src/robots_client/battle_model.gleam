//// Battles: the order, the battle being fought, its report, and their
//// messages.

import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import robots/ai/brain
import robots/construction/robot.{type Robot}
import robots/rules/game.{type Game}
import robots/run/state.{type Run}

/// Battles during a run: the order robots go in, the battle being fought,
/// and the report of the last one (until the player continues).
pub type Combat {
  Combat(order: List(Int), battle: Option(Battle), report: Option(Report))
}

pub fn new_combat(run: Run) -> Combat {
  Combat(order: default_order(run), battle: None, report: None)
}

pub type Battle {
  Battle(
    game: Game,
    brain: brain.Brain,
    order: List(Int),
    /// The player's robots as they entered, in order.
    team: List(Robot),
    enemy: String,
    started: Int,
  )
}

pub type Report {
  Report(
    won: Bool,
    enemy: String,
    enemy_hp: Float,
    enemy_max_hp: Float,
    /// Each robot that fought: name, HP before, HP after, max HP.
    robots: List(#(String, Float, Float, Float)),
    seconds: Int,
    reward: state.Reward,
    /// The run's level before and after (a boss moves it on).
    level_before: Int,
    level_after: Int,
  )
}

/// Messages before, during and after a battle.
pub type Msg {
  /// Send this robot in first.
  First(robot: Int)
  Fight
  Play(slot: Int)
  /// Leave the battle report.
  Continue
}

pub fn default_order(run: Run) -> List(Int) {
  int.range(0, list.length(run.robots), [], list.prepend) |> list.reverse
}
