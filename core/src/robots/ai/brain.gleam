//// A simple, pure AI opponent that reacts like a human.
////
//// Each step it works out what it would do right now (play a card or wait).
//// When that intent changes (a card became affordable, the opponent's play
//// changed the best answer, a new card was drawn) it waits a random
//// reaction delay, then acts if its intent is still the same. After playing,
//// the next situation is new again, so every play takes a reaction.
////
//// It can see both tables (everyone can) and rates every card on its own
//// table by *efficiency*: how much the card would achieve right now, per
//// energy spent. It plays the most efficient card, and when that card isn't
//// affordable yet it saves energy for it instead of spending on cheap filler.
//// It spends on the best affordable card only when energy is about to cap.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import robots/rules/amount
import robots/rules/card.{type Scope, All, One}
import robots/rules/energy
import robots/rules/game.{type Game, type Side, PlayCard, Running}
import robots/rules/rng.{type Seed}
import robots/rules/table.{type Slot}

/// How long it takes to react to a change, in ms (picked at random).
pub type Reaction {
  Reaction(min_ms: Int, max_ms: Int)
}

/// A human-like reaction: 0.5 to 0.8 s.
pub const human = Reaction(min_ms: 500, max_ms: 800)

pub type Brain {
  Brain(
    side: Side,
    reaction: Reaction,
    /// What it means to do (`Ok(#(slot, card))` or `Error(Nil)` = wait),
    /// as of the last change it noticed; `None` right after it played.
    intent: Option(Result(#(Int, String), Nil)),
    /// When it will act on `intent`.
    act_at: Int,
    seed: Seed,
  )
}

/// Energy this close to the cap would be wasted by waiting longer.
const nearly_full = 0.9

const finishing_blow = 1000.0

pub fn new(side: Side, reaction reaction: Reaction, seed seed: Int) -> Brain {
  Brain(side:, reaction:, intent: None, act_at: 0, seed: rng.new(seed))
}

/// Call often (every frame or simulation step). Plays at most one card.
pub fn act(brain: Brain, state: Game, now: Int) -> #(Brain, Game) {
  case state.status {
    Running -> {
      let intent = intent(state, brain.side, now)
      case brain.intent == Some(intent), intent {
        // Something changed: react to it after a delay.
        False, _ -> {
          let #(delay, seed) = reaction_delay(brain)
          #(
            Brain(..brain, intent: Some(intent), act_at: now + delay, seed:),
            state,
          )
        }
        // Same plan as before, and the reaction time has passed.
        True, Ok(#(slot, _)) if now >= brain.act_at ->
          case game.update(state, PlayCard(brain.side, slot, now)) {
            Ok(state) -> #(Brain(..brain, intent: None), state)
            Error(_) -> #(Brain(..brain, intent: None), state)
          }
        True, _ -> #(brain, state)
      }
    }
    _ -> #(brain, state)
  }
}

/// The slot it would play now and which card is there, or `Error(Nil)`.
fn intent(state: Game, side: Side, now: Int) -> Result(#(Int, String), Nil) {
  case choose(state, side, now) {
    Ok(slot) ->
      case list.drop(game.combatant_of(state, side).table, slot) {
        [s, ..] -> Ok(#(slot, s.card.name))
        [] -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn reaction_delay(brain: Brain) -> #(Int, Seed) {
  let Reaction(min_ms:, max_ms:) = brain.reaction
  let #(extra, seed) = rng.int_below(brain.seed, max_ms - min_ms + 1)
  #(min_ms + extra, seed)
}

type Choice {
  Choice(slot: Int, cost: Float, score: Float, affordable: Bool, drone: Bool)
}

/// The table slot to play now, or `Error(Nil)` to wait (save energy).
pub fn choose(state: Game, side: Side, now: Int) -> Result(Int, Nil) {
  // Read current values: drones have grown since they were placed.
  let state = game.settle(state, now)
  let me = game.combatant_of(state, side)
  let available = energy.at(me.energy, now)
  let options =
    me.table
    |> list.index_map(fn(s, slot) {
      Choice(
        slot:,
        cost: s.card.cost,
        score: score(state, side, s),
        affordable: amount.at_least(available, s.card.cost),
        drone: table.is_drone(s),
      )
    })
    // A card costing more than the cap can never be paid for.
    |> list.filter(fn(o) { amount.at_least(me.energy.cap, o.cost) })
  let useful = list.filter(options, fn(o) { o.score >. 0.0 })
  let full = available >=. me.energy.cap *. nearly_full
  case most_efficient(useful), full {
    // The best card is affordable: play it.
    Ok(best), _ if best.affordable -> Ok(best.slot)
    // Energy is about to be wasted: spend it on the best thing we can afford,
    // or clear a dead slot.
    _, True ->
      case most_efficient(list.filter(useful, fn(o) { o.affordable })) {
        Ok(o) -> Ok(o.slot)
        // A drone is never dead weight: let it keep growing.
        Error(Nil) ->
          cheapest(list.filter(options, fn(o) { o.affordable && !o.drone }))
      }
    // Save up for the best card.
    _, False -> Error(Nil)
  }
}

fn efficiency(o: Choice) -> Float {
  case o.cost >. 0.0 {
    True -> o.score /. o.cost
    False -> o.score *. 100.0
  }
}

fn most_efficient(options: List(Choice)) -> Result(Choice, Nil) {
  list.max(options, fn(a, b) {
    case float.compare(efficiency(a), efficiency(b)) {
      order.Eq -> float.compare(a.score, b.score)
      other -> other
    }
  })
}

fn cheapest(options: List(Choice)) -> Result(Int, Nil) {
  case list.max(options, fn(a, b) { float.compare(b.cost, a.cost) }) {
    Ok(o) -> Ok(o.slot)
    Error(Nil) -> Error(Nil)
  }
}

/// Roughly "how much value this card delivers right now".
fn score(state: Game, side: Side, slot: Slot) -> Float {
  let foe = game.combatant_of(state, game.other(side))
  let me = game.combatant_of(state, side)
  let foe_drones = list.filter(foe.table, table.is_drone)
  case slot.card.target {
    card.OpponentHp ->
      case still_growing(slot), foe_drones {
        // A drone waits until fully grown, unless it would win the match.
        True, [] if slot.value >=. foe.robot.hp -> finishing_blow
        True, _ -> 0.0
        // Their drones soak up attacks: expect to hit one of them.
        False, [_, ..] ->
          scope_score(foe_drones, All([card.Drone]), fn(d) {
            float.min(d.value, slot.value)
          })
          /. int.to_float(list.length(foe_drones))
        False, [] if slot.value >=. foe.robot.hp -> finishing_blow
        False, [] -> slot.value
      }
    // Worth what the drone will grow into.
    card.Launch(drone) ->
      case card.growth(drone) {
        Ok(#(_, cap)) -> cap
        Error(Nil) -> drone.value
      }
    card.Opponent(scope) ->
      scope_score(foe.table, scope, fn(target) {
        target.value
        -. game.lowered(target, slot.value, state.config.defence_floor)
      })
    card.Self(scope) -> scope_score(me.table, scope, fn(_) { slot.value })
    // Worth the card it destroys for the rest of the match.
    card.Burn(_) -> {
      let burnable =
        list.filter(foe.table, table.burnable)
        |> list.map(fn(s) { s.card.value })
      case burnable {
        [] -> 0.0
        _ -> float.sum(burnable) /. int.to_float(list.length(burnable))
      }
    }
    card.NoEffect -> 0.0
    // Worth what it takes off their cards, minus what it takes off ours.
    card.Both(scope) -> {
      let cut = fn(target: Slot) {
        target.value
        -. game.lowered(target, slot.value, state.config.defence_floor)
      }
      scope_score(foe.table, scope, cut) -. scope_score(me.table, scope, cut)
    }
  }
}

/// A drone that hasn't reached its cap yet is better left to grow.
fn still_growing(slot: Slot) -> Bool {
  case card.growth(slot.card) {
    Ok(#(_, cap)) -> !amount.at_least(slot.value, cap)
    Error(Nil) -> False
  }
}

/// Total effect for `All`, expected (average) effect for `One`.
fn scope_score(
  targets: List(Slot),
  scope: Scope,
  effect: fn(Slot) -> Float,
) -> Float {
  let gains = case scope {
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
