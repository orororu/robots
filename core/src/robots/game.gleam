//// The whole game as a pure state machine:
////
////     update(game, msg) -> Result(Game, Rejection)
////
//// Every message carries its own timestamp (milliseconds). The core never
//// reads a clock and never does IO, so it runs unchanged in the browser, in
//// tests, and (later) on a BEAM server for PvP.

import gleam/int
import gleam/list
import gleam/result
import robots/card.{type Card, type Effect}
import robots/energy.{type Energy}
import robots/rng.{type Seed}
import robots/robot.{type Robot}

pub type Side {
  P1
  P2
}

pub fn other(side: Side) -> Side {
  case side {
    P1 -> P2
    P2 -> P1
  }
}

pub type Config {
  Config(
    starting_hand: Int,
    hand_limit: Int,
    draw_interval_ms: Int,
    starting_energy: Float,
    energy_rate: Float,
    energy_cap: Float,
  )
}

pub fn default_config() -> Config {
  Config(
    starting_hand: 3,
    hand_limit: 5,
    draw_interval_ms: 2500,
    starting_energy: 3.0,
    energy_rate: 1.0,
    energy_cap: 10.0,
  )
}

pub type Combatant {
  Combatant(
    robot: Robot,
    deck: List(Card),
    hand: List(Card),
    discard: List(Card),
    energy: Energy,
    next_draw_at: Int,
  )
}

pub type Status {
  Running
  Won(Side)
}

pub type Game {
  Game(
    config: Config,
    p1: Combatant,
    p2: Combatant,
    seed: Seed,
    status: Status,
    log: List(String),
  )
}

pub type Msg {
  PlayCard(side: Side, hand_index: Int, at: Int)
  /// Let time pass: performs any card draws that are due.
  Tick(at: Int)
}

pub type Rejection {
  GameOver
  NoSuchCard
  NotEnoughEnergy(cost: Int, available: Float)
}

const log_length = 6

pub fn new(
  config: Config,
  p1 p1_robot: Robot,
  p2 p2_robot: Robot,
  seed seed: Int,
  now now: Int,
) -> Game {
  let seed = rng.new(seed)
  let #(p1, seed) = combatant(config, p1_robot, seed, now)
  let #(p2, seed) = combatant(config, p2_robot, seed, now)
  Game(config:, p1:, p2:, seed:, status: Running, log: ["Fight!"])
}

fn combatant(
  config: Config,
  bot: Robot,
  seed: Seed,
  now: Int,
) -> #(Combatant, Seed) {
  let #(deck, seed) = rng.shuffle(robot.deck(bot), seed)
  let #(hand, deck) = list.split(deck, config.starting_hand)
  let energy =
    energy.new(
      config.starting_energy,
      rate: config.energy_rate,
      cap: config.energy_cap,
      now:,
    )
  let combatant =
    Combatant(
      robot: bot,
      deck:,
      hand:,
      discard: [],
      energy:,
      next_draw_at: now + config.draw_interval_ms,
    )
  #(combatant, seed)
}

pub fn combatant_of(game: Game, side: Side) -> Combatant {
  case side {
    P1 -> game.p1
    P2 -> game.p2
  }
}

fn put(game: Game, side: Side, combatant: Combatant) -> Game {
  case side {
    P1 -> Game(..game, p1: combatant)
    P2 -> Game(..game, p2: combatant)
  }
}

pub fn update(game: Game, msg: Msg) -> Result(Game, Rejection) {
  case game.status, msg {
    Won(_), Tick(_) -> Ok(game)
    Won(_), PlayCard(..) -> Error(GameOver)
    Running, Tick(at) -> Ok(tick(game, at))
    Running, PlayCard(side, index, at) -> play(game, side, index, at)
  }
}

// TIME ------------------------------------------------------------------------

fn tick(game: Game, now: Int) -> Game {
  game
  |> draw_due(P1, now)
  |> draw_due(P2, now)
}

fn draw_due(game: Game, side: Side, now: Int) -> Game {
  let c = combatant_of(game, side)
  case now >= c.next_draw_at {
    False -> game
    True -> {
      // A full hand skips the draw, but the draw timer keeps running.
      let game = case list.length(c.hand) < game.config.hand_limit {
        True -> draw(game, side)
        False -> game
      }
      let c = combatant_of(game, side)
      let next_draw_at = c.next_draw_at + game.config.draw_interval_ms
      game
      |> put(side, Combatant(..c, next_draw_at:))
      |> draw_due(side, now)
    }
  }
}

fn draw(game: Game, side: Side) -> Game {
  let c = combatant_of(game, side)
  case c.deck, c.discard {
    [card, ..deck], _ ->
      put(game, side, Combatant(..c, deck:, hand: list.append(c.hand, [card])))
    [], [] -> game
    [], discard -> {
      let #(deck, seed) = rng.shuffle(discard, game.seed)
      Game(..game, seed:)
      |> put(side, Combatant(..c, deck:, discard: []))
      |> draw(side)
    }
  }
}

// PLAYING CARDS ---------------------------------------------------------------

fn play(
  game: Game,
  side: Side,
  index: Int,
  now: Int,
) -> Result(Game, Rejection) {
  let c = combatant_of(game, side)
  use #(card, hand) <- result.try(
    take_at(c.hand, index) |> result.replace_error(NoSuchCard),
  )
  use spent <- result.try(
    energy.spend(c.energy, int.to_float(card.cost), now)
    |> result.map_error(NotEnoughEnergy(card.cost, _)),
  )
  let game =
    put(
      game,
      side,
      Combatant(..c, hand:, energy: spent, discard: [card, ..c.discard]),
    )
  let game =
    list.fold(card.effects, game, fn(game, effect) {
      apply(game, side, effect, now)
    })
  game
  |> log(
    c.robot.name <> " plays " <> card.name <> " (" <> card.describe(card) <> ")",
  )
  |> check_winner
  |> Ok
}

fn apply(game: Game, side: Side, effect: Effect, now: Int) -> Game {
  case effect {
    card.Damage(n) -> map_robot(game, other(side), robot.take_damage(_, n))
    card.Shield(n) -> map_robot(game, side, robot.add_shield(_, n))
    card.Repair(n) -> map_robot(game, side, robot.repair(_, n))
    card.Charge(x) -> {
      let c = combatant_of(game, side)
      put(game, side, Combatant(..c, energy: energy.gain(c.energy, x, now)))
    }
  }
}

fn map_robot(game: Game, side: Side, f: fn(Robot) -> Robot) -> Game {
  let c = combatant_of(game, side)
  put(game, side, Combatant(..c, robot: f(c.robot)))
}

fn check_winner(game: Game) -> Game {
  case robot.is_destroyed(game.p1.robot), robot.is_destroyed(game.p2.robot) {
    _, True ->
      Game(..game, status: Won(P1))
      |> log(game.p2.robot.name <> " is destroyed!")
    True, False ->
      Game(..game, status: Won(P2))
      |> log(game.p1.robot.name <> " is destroyed!")
    False, False -> game
  }
}

fn log(game: Game, entry: String) -> Game {
  Game(..game, log: list.take([entry, ..game.log], log_length))
}

fn take_at(items: List(a), index: Int) -> Result(#(a, List(a)), Nil) {
  case index >= 0, list.split(items, index) {
    True, #(before, [item, ..after]) -> Ok(#(item, list.append(before, after)))
    _, _ -> Error(Nil)
  }
}
