//// A battle's steps, pure: start it, let time pass (the AI acts), play a
//// card, and once it's over, report it to the run. `update` supplies the
//// clock and the random seeds, and saves the run.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import robots/ai/brain
import robots/content/enemies
import robots/rules/game.{P1, P2}
import robots/run/state.{type Run}
import robots_client/model.{type Battle, type Report, Battle, Report}

/// The battle at the run's current node, with the robots in `order`.
pub fn start(
  run: Run,
  order: List(Int),
  now: Int,
  seed: Int,
  brain_seed: Int,
) -> Result(Battle, state.Error) {
  use #(_, enemy) <- result.try(state.battle(run))
  use team <- result.map(state.team(run, order))
  let game =
    game.teams(
      game.default_config(),
      p1: team,
      p2: [enemies.robot(enemy)],
      seed:,
      now:,
    )
  Battle(
    game:,
    brain: brain.new(P2, reaction: brain.human, seed: brain_seed),
    order:,
    team:,
    enemy: enemy.name,
    started: now,
  )
}

/// Let time pass and give the AI a chance to act.
pub fn tick(b: Battle, now: Int) -> Battle {
  let #(brain, game) = brain.act(b.brain, b.game, now)
  Battle(..b, game:, brain:)
}

/// The player plays the card in `slot`.
pub fn play(b: Battle, slot: Int, now: Int) -> Result(Battle, game.Rejection) {
  use game <- result.map(game.update(b.game, game.PlayCard(P1, slot, now)))
  Battle(..b, game:)
}

/// Once the battle is over: the run after it (damage, losses, loot) and the
/// report. `None` while it's still running.
pub fn finish(
  run: Run,
  b: Battle,
  now: Int,
) -> Result(Option(#(Run, Report)), state.Error) {
  use <- guard_running(b)
  let outcome = state.outcome(b.game, list.length(b.order))
  use #(after, reward) <- result.map(state.finish(run, b.order, outcome))
  Some(#(
    after,
    Report(
      won: outcome.won,
      enemy: b.enemy,
      enemy_hp: b.game.p2.robot.hp,
      enemy_max_hp: b.game.p2.robot.max_hp,
      robots: list.map(list.zip(b.team, outcome.hp_left), fn(pair) {
        let #(r, hp) = pair
        #(r.name, r.hp, hp, r.max_hp)
      }),
      seconds: { now - b.started } / 1000,
      reward:,
      level_before: run.level,
      level_after: after.level,
    ),
  ))
}

fn guard_running(
  b: Battle,
  then: fn() -> Result(Option(a), e),
) -> Result(Option(a), e) {
  case b.game.status == game.Running {
    True -> Ok(None)
    False -> then()
  }
}
