//// The whole game as a pure state machine:
////
////     update(game, msg) -> Result(Game, Rejection)
////
//// Every message carries its own timestamp (milliseconds). The core never
//// reads a clock and never does IO, so it runs unchanged in the browser, in
//// tests, and (later) on a BEAM server for PvP.
////
//// Rules: see docs/RULES.md. In short, each side has a table of 4 visible
//// cards. Playing one costs energy, resolves it once, discards it and draws a
//// replacement into the same slot. There's no hand, no draw timer and no
//// discard action.

import gleam/float
import gleam/list
import gleam/result
import robots/amount
import robots/card.{type Card}
import robots/energy.{type Energy}
import robots/rng.{type Seed}
import robots/robot.{type Robot}
import robots/table.{type Slot}

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

/// Energy amounts are relative, on the same scale as card costs. The energy
/// cap is not here: each robot's batteries decide it.
pub type Config {
  Config(
    table_size: Int,
    starting_energy: Float,
    energy_rate: Float,
    /// Defence can't lower a card below this share of its printed value
    /// (0.25 = a quarter). Every attack that gets played still hurts, so two
    /// defensive builds can't stall each other forever.
    defence_floor: Float,
  )
}

pub fn default_config() -> Config {
  Config(
    table_size: 4,
    starting_energy: 2.0,
    // Relative cost units per second: 0.5 / 3 shows as ~1.7/s at scale x10.
    energy_rate: 0.5 /. 3.0,
    // Off for now; see docs/RULES.md "Defence floor".
    defence_floor: 0.0,
  )
}

pub type Combatant {
  Combatant(
    robot: Robot,
    deck: List(Card),
    table: List(Slot),
    discard: List(Card),
    energy: Energy,
  )
}

pub type Status {
  Running
  Won(Side)
}

/// What happened, as data. The client decides how to word and scale it.
pub type Event {
  Started
  /// `value` is the card's value when played; `targets` is how many things
  /// it affected: 1 for HP, the number of table cards otherwise (0 = no match).
  /// `effect` is the total amount actually changed: damage dealt, HP
  /// or table value lowered/raised (extra value is not counted).
  Played(side: Side, card: Card, value: Float, targets: Int, effect: Float)
  Destroyed(side: Side)
}

pub type Game {
  Game(
    config: Config,
    p1: Combatant,
    p2: Combatant,
    seed: Seed,
    status: Status,
    log: List(Event),
  )
}

pub type Msg {
  PlayCard(side: Side, slot: Int, at: Int)
}

pub type Rejection {
  GameOver
  NoSuchCard
  NotEnoughEnergy(cost: Float, available: Float)
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
  Game(config:, p1:, p2:, seed:, status: Running, log: [Started])
}

fn combatant(
  config: Config,
  bot: Robot,
  seed: Seed,
  now: Int,
) -> #(Combatant, Seed) {
  let #(deck, seed) = rng.shuffle(robot.deck(bot), seed)
  let energy =
    energy.new(
      config.starting_energy,
      rate: config.energy_rate,
      cap: bot.energy_cap,
      now:,
    )
  Combatant(robot: bot, deck:, table: [], discard: [], energy:)
  |> fill_table(config.table_size, seed)
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
    Won(_), _ -> Error(GameOver)
    Running, PlayCard(side, slot, at) -> play(game, side, slot, at)
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
  use #(played, rest) <- result.try(
    take_at(c.table, index) |> result.replace_error(NoSuchCard),
  )
  use spent <- result.try(
    energy.spend(c.energy, played.card.cost, now)
    |> result.map_error(NotEnoughEnergy(played.card.cost, _)),
  )
  // The card leaves the table before it resolves, so a buff can't target
  // itself. `Once` cards leave the game; the rest go to the discard pile.
  let discard = case card.has_trait(played.card, card.Once) {
    True -> c.discard
    False -> [played.card, ..c.discard]
  }
  let game =
    put(game, side, Combatant(..c, table: rest, energy: spent, discard:))
  let #(game, targets, effect) = resolve(game, side, played)
  let #(refilled, seed) = refill(combatant_of(game, side), index, game.seed)
  Game(..game, seed:)
  |> put(side, refilled)
  |> log(Played(side, played.card, played.value, targets, effect))
  |> check_winner
  |> Ok
}

/// Returns the new game, how many things were affected (1 for HP, else the
/// number of table cards), and the total amount actually changed.
fn resolve(game: Game, side: Side, played: Slot) -> #(Game, Int, Float) {
  let value = played.value
  // Opponent lowers, Self raises; the scope says what.
  case played.card.target {
    card.OpponentHp -> map_robot(game, other(side), robot.take_damage(_, value))
    card.Opponent(scope) ->
      affect_table(game, other(side), scope, lowered(
        _,
        value,
        game.config.defence_floor,
      ))
    card.Self(scope) ->
      affect_table(game, side, scope, fn(s: Slot) { s.value +. value })
  }
}

fn map_robot(
  game: Game,
  side: Side,
  f: fn(Robot) -> Robot,
) -> #(Game, Int, Float) {
  let c = combatant_of(game, side)
  let changed = f(c.robot)
  let effect = float.absolute_value(changed.hp -. c.robot.hp)
  #(put(game, side, Combatant(..c, robot: changed)), 1, effect)
}

/// A table card's value after a defence of `by`: never below `floor` times
/// its printed value (nor raised, if it is already lower).
pub fn lowered(slot: Slot, by: Float, floor: Float) -> Float {
  let minimum = float.min(slot.value, floor *. slot.card.value)
  float.max(amount.subtract(slot.value, by), minimum)
}

fn affect_table(
  game: Game,
  side: Side,
  scope: card.Scope,
  change: fn(Slot) -> Float,
) -> #(Game, Int, Float) {
  let c = combatant_of(game, side)
  let #(table, targets, seed) = table.affect(c.table, scope, change, game.seed)
  let effect =
    list.zip(c.table, table)
    |> list.fold(0.0, fn(total, pair) {
      total +. float.absolute_value({ pair.1 }.value -. { pair.0 }.value)
    })
  #(Game(..game, seed:) |> put(side, Combatant(..c, table:)), targets, effect)
}

// DRAWING ---------------------------------------------------------------------

fn fill_table(c: Combatant, size: Int, seed: Seed) -> #(Combatant, Seed) {
  case list.length(c.table) < size {
    False -> #(c, seed)
    True ->
      case draw(c, seed) {
        Ok(#(card, c, seed)) ->
          Combatant(..c, table: list.append(c.table, [table.slot(card)]))
          |> fill_table(size, seed)
        Error(Nil) -> #(c, seed)
      }
  }
}

/// Draw into the slot that was just played, so other cards keep their places.
fn refill(c: Combatant, index: Int, seed: Seed) -> #(Combatant, Seed) {
  case draw(c, seed) {
    Ok(#(card, c, seed)) -> {
      let #(before, after) = list.split(c.table, index)
      let table = list.flatten([before, [table.slot(card)], after])
      #(Combatant(..c, table:), seed)
    }
    Error(Nil) -> #(c, seed)
  }
}

/// Take the top card of the deck, reshuffling the discard pile when the deck
/// is empty. Fails only when both are empty.
fn draw(c: Combatant, seed: Seed) -> Result(#(Card, Combatant, Seed), Nil) {
  case c.deck, c.discard {
    [card, ..deck], _ -> Ok(#(card, Combatant(..c, deck:), seed))
    [], [] -> Error(Nil)
    [], discard -> {
      let #(deck, seed) = rng.shuffle(discard, seed)
      draw(Combatant(..c, deck:, discard: []), seed)
    }
  }
}

// HELPERS ---------------------------------------------------------------------

fn check_winner(game: Game) -> Game {
  case robot.is_destroyed(game.p1.robot), robot.is_destroyed(game.p2.robot) {
    _, True -> Game(..game, status: Won(P1)) |> log(Destroyed(P2))
    True, False -> Game(..game, status: Won(P2)) |> log(Destroyed(P1))
    False, False -> game
  }
}

fn log(game: Game, event: Event) -> Game {
  Game(..game, log: list.take([event, ..game.log], log_length))
}

fn take_at(items: List(a), index: Int) -> Result(#(a, List(a)), Nil) {
  case index >= 0, list.split(items, index) {
    True, #(before, [item, ..after]) -> Ok(#(item, list.append(before, after)))
    _, _ -> Error(Nil)
  }
}
