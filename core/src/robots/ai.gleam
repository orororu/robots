//// A simple, pure AI opponent. It "thinks" for `think_ms` between plays.
//// It can see both tables (everyone can), scores every affordable card by
//// how much it would achieve right now, and plays the best one.

import gleam/float
import gleam/int
import gleam/list
import robots/amount
import robots/card.{type Scope, All, Hp, One}
import robots/energy
import robots/game.{type Game, type Side, PlayCard, Running}
import robots/table.{type Slot}

pub type Brain {
  Brain(side: Side, think_ms: Int, next_action_at: Int)
}

/// How soon to look again when nothing was worth playing.
const recheck_ms = 250

/// Played only to clear a slot: when energy is nearly full and nothing better
/// is available, a dead card is worth getting rid of.
const clog_threshold = 0.9

pub fn new(side: Side, think_ms think_ms: Int, now now: Int) -> Brain {
  Brain(side:, think_ms:, next_action_at: now + think_ms)
}

pub fn act(brain: Brain, state: Game, now: Int) -> #(Brain, Game) {
  case state.status, now >= brain.next_action_at {
    Running, True -> {
      let played =
        choose(state, brain.side, now)
        |> result_try_play(state, brain.side, now)
      case played {
        Ok(state) -> #(
          Brain(..brain, next_action_at: now + brain.think_ms),
          state,
        )
        Error(Nil) -> #(Brain(..brain, next_action_at: now + recheck_ms), state)
      }
    }
    _, _ -> #(brain, state)
  }
}

fn result_try_play(
  choice: Result(Int, Nil),
  state: Game,
  side: Side,
  now: Int,
) -> Result(Game, Nil) {
  case choice {
    Ok(slot) ->
      case game.update(state, PlayCard(side, slot, now)) {
        Ok(state) -> Ok(state)
        Error(_) -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

/// The table slot to play, if any card is affordable and worth playing.
pub fn choose(state: Game, side: Side, now: Int) -> Result(Int, Nil) {
  let me = game.combatant_of(state, side)
  let available = energy.at(me.energy, now)
  let affordable =
    me.table
    |> list.index_map(fn(s, index) { #(index, s) })
    |> list.filter(fn(pair) { amount.at_least(available, { pair.1 }.card.cost) })
  let scored =
    list.map(affordable, fn(pair) { #(pair.0, score(state, side, pair.1)) })
  case best(scored) {
    Ok(#(index, s)) if s >. 0.0 -> Ok(index)
    _ ->
      case available >=. me.energy.cap *. clog_threshold {
        True -> cheapest(affordable)
        False -> Error(Nil)
      }
  }
}

fn best(scored: List(#(Int, Float))) -> Result(#(Int, Float), Nil) {
  list.fold(scored, Error(Nil), fn(best, candidate) {
    case best {
      Ok(#(_, best_score)) if best_score >=. candidate.1 -> best
      _ -> Ok(candidate)
    }
  })
}

fn cheapest(slots: List(#(Int, Slot))) -> Result(Int, Nil) {
  slots
  |> list.sort(fn(a, b) { float.compare({ a.1 }.card.cost, { b.1 }.card.cost) })
  |> list.first
  |> result_index
}

fn result_index(pair: Result(#(Int, Slot), Nil)) -> Result(Int, Nil) {
  case pair {
    Ok(#(index, _)) -> Ok(index)
    Error(Nil) -> Error(Nil)
  }
}

/// Roughly "how much value this card delivers right now".
fn score(state: Game, side: Side, slot: Slot) -> Float {
  let foe = game.combatant_of(state, game.other(side))
  let me = game.combatant_of(state, side)
  case slot.card.target {
    card.Opponent(Hp) ->
      case amount.at_least(slot.value, foe.robot.hp) {
        // A finishing blow beats everything.
        True -> 100.0
        False -> slot.value
      }
    card.Self(Hp) -> float.min(slot.value, me.robot.max_hp -. me.robot.hp)
    card.Opponent(scope) ->
      scope_score(foe.table, scope, fn(target) {
        float.min(target.value, slot.value)
      })
    card.Self(scope) -> scope_score(me.table, scope, fn(_) { slot.value })
  }
}

/// Total effect for `All`, expected (average) effect for `One`.
fn scope_score(
  targets: List(Slot),
  scope: Scope,
  effect: fn(Slot) -> Float,
) -> Float {
  let gains = case scope {
    Hp -> []
    All(tags) | One(tags) ->
      targets
      |> list.filter(fn(s) { card.matches(s.card, tags) })
      |> list.map(effect)
      |> list.filter(fn(gain) { gain >. 0.0 })
  }
  let total = float.sum(gains)
  case scope, gains {
    One(_), [_, ..] -> total /. int.to_float(list.length(gains))
    _, _ -> total
  }
}
