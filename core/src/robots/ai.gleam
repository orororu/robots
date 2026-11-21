//// A simple, pure AI opponent. It "thinks" for `think_ms` between plays and
//// greedily picks the best-scoring card it can afford right now.

import gleam/float
import gleam/int
import gleam/list
import robots/card.{type Card}
import robots/energy
import robots/game.{type Game, type Side, PlayCard, Running}

pub type Brain {
  Brain(side: Side, think_ms: Int, next_action_at: Int)
}

/// How soon to look again when nothing was affordable.
const recheck_ms = 250

pub fn new(side: Side, think_ms think_ms: Int, now now: Int) -> Brain {
  Brain(side:, think_ms:, next_action_at: now + think_ms)
}

pub fn act(brain: Brain, state: Game, now: Int) -> #(Brain, Game) {
  case state.status, now >= brain.next_action_at {
    Running, True ->
      case choose(state, brain.side, now) {
        Ok(index) ->
          case game.update(state, PlayCard(brain.side, index, now)) {
            Ok(state) -> #(
              Brain(..brain, next_action_at: now + brain.think_ms),
              state,
            )
            Error(_) -> #(
              Brain(..brain, next_action_at: now + recheck_ms),
              state,
            )
          }
        Error(_) -> #(Brain(..brain, next_action_at: now + recheck_ms), state)
      }
    _, _ -> #(brain, state)
  }
}

/// The hand index of the card to play, if any is affordable.
pub fn choose(state: Game, side: Side, now: Int) -> Result(Int, Nil) {
  let me = game.combatant_of(state, side)
  let available = energy.at(me.energy, now)
  me.hand
  |> list.index_map(fn(card, index) { #(index, card) })
  |> list.filter(fn(pair) { int.to_float({ pair.1 }.cost) <=. available })
  |> list.map(fn(pair) { #(pair.0, score(state, side, pair.1)) })
  |> list.fold(Error(Nil), fn(best, candidate) {
    case best {
      Ok(#(_, best_score)) if best_score >= candidate.1 -> best
      _ -> Ok(candidate)
    }
  })
  |> result_index
}

fn result_index(best: Result(#(Int, Int), Nil)) -> Result(Int, Nil) {
  case best {
    Ok(#(index, _)) -> Ok(index)
    Error(Nil) -> Error(Nil)
  }
}

fn score(state: Game, side: Side, card: Card) -> Int {
  let me = game.combatant_of(state, side).robot
  let missing_hp = me.max_hp - me.hp
  list.fold(card.effects, 0, fn(total, effect) {
    total
    + case effect {
      card.Damage(n) -> n * 10
      card.Shield(n) if me.shield < 5 -> n * 6
      card.Shield(n) -> n * 2
      card.Repair(n) -> int.min(n, missing_hp) * 12
      card.Charge(x) -> float.round(x *. 4.0)
    }
  })
}
