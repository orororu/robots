//// Battles, pure: the order, starting a battle, letting time pass (the AI
//// acts), playing cards, and reporting a finished battle to the run. The
//// root supplies the clock and the seeds, saves the run and shows messages.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import robots/ai/brain
import robots/content/enemies
import robots/rules/game.{P1, P2}
import robots/run/state.{type Run}
import robots_client/battle/model.{
  type Battle, type Combat, type Msg, type Report, Battle, Combat, Continue,
  Fight, First, Play, Report, default_order,
}

/// What a message did beyond the combat state.
pub type Outcome {
  Nothing
  /// A card was played.
  Played
  Rejected(game.Rejection)
  Failed(state.Error)
  /// The battle is over: the run after it (damage, losses, loot) and its
  /// report.
  Over(run: Run, report: Report)
}

/// The clock and the seeds a message may use.
pub type Env {
  Env(now: Int, seed: Int, brain_seed: Int)
}

pub fn update(c: Combat, run: Run, msg: Msg, env: Env) -> #(Combat, Outcome) {
  case msg {
    First(robot) -> #(
      Combat(..c, order: [robot, ..list.filter(c.order, fn(i) { i != robot })]),
      Nothing,
    )
    Continue -> #(Combat(..c, report: None), Nothing)
    Fight ->
      case start(run, c.order, env.now, env.seed, env.brain_seed) {
        Ok(b) -> #(Combat(..c, battle: Some(b)), Nothing)
        Error(e) -> #(c, Failed(e))
      }
    Play(slot) ->
      // Catch up to now first: the last frame may be up to 50ms old.
      case advance(c, run, env.now) {
        #(Combat(battle: Some(b), ..) as c, Nothing) ->
          case play(b, slot, env.now) {
            Ok(b) ->
              case end_if_over(Combat(..c, battle: Some(b)), run, env.now) {
                #(c, Nothing) -> #(c, Played)
                over -> over
              }
            Error(rejection) -> #(c, Rejected(rejection))
          }
        other -> other
      }
  }
}

/// Let time pass: the AI acts, and a battle that's over is reported.
pub fn advance(c: Combat, run: Run, now: Int) -> #(Combat, Outcome) {
  case c.battle {
    Some(b) -> end_if_over(Combat(..c, battle: Some(tick(b, now))), run, now)
    None -> #(c, Nothing)
  }
}

/// A finished battle stops (no more ticking) and is reported.
fn end_if_over(c: Combat, run: Run, now: Int) -> #(Combat, Outcome) {
  case c.battle {
    None -> #(c, Nothing)
    Some(b) ->
      case finish(run, b, now) {
        Ok(None) -> #(c, Nothing)
        Ok(Some(#(after, report))) -> #(
          Combat(
            order: default_order(after),
            battle: None,
            report: Some(report),
          ),
          Over(after, report),
        )
        Error(e) -> #(c, Failed(e))
      }
  }
}

/// The battle at the run's current node, with the robots in `order`.
fn start(
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
fn tick(b: Battle, now: Int) -> Battle {
  let #(brain, game) = brain.act(b.brain, b.game, now)
  Battle(..b, game:, brain:)
}

/// The player plays the card in `slot`.
fn play(b: Battle, slot: Int, now: Int) -> Result(Battle, game.Rejection) {
  use game <- result.map(game.update(b.game, game.PlayCard(P1, slot, now)))
  Battle(..b, game:)
}

/// Once the battle is over: the run after it (damage, losses, loot) and the
/// report. `None` while it's still running.
fn finish(
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
