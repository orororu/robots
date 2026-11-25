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
import robots/construction/robot.{type Robot}
import robots/rules/amount
import robots/rules/card.{type Card}
import robots/rules/energy.{type Energy}
import robots/rules/rng.{type Seed}
import robots/rules/table.{type Slot, Slot}

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
    // Start empty, so nobody has to play in the first second.
    starting_energy: 0.0,
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
    /// Robots waiting to fight, in order. When `robot` is destroyed, the
    /// next one enters; the side loses when none are left.
    reserve: List(Robot),
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
  /// An attack hit one of `side`'s drones instead of the robot. Damage
  /// beyond the drone's value is lost.
  DroneHit(side: Side, drone: Card, damage: Float, destroyed: Bool)
  /// One of `side`'s drones was lowered to 0 by a table effect (e.g. Shoot down).
  DroneDestroyed(side: Side, drone: Card)
  /// One of `side`'s cards was burnt: it left the match, and a Fire card
  /// took its slot.
  Burned(side: Side, card: Card)
  Destroyed(side: Side)
  /// `side`'s next robot entered the battle after the last was destroyed.
  Entered(side: Side, robot: Robot)
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
  teams(config, p1: [p1_robot], p2: [p2_robot], seed:, now:)
}

/// A battle between teams: each side's robots fight one at a time, in the
/// given order. Both lists must be non-empty.
pub fn teams(
  config: Config,
  p1 p1_team: List(Robot),
  p2 p2_team: List(Robot),
  seed seed: Int,
  now now: Int,
) -> Game {
  let seed = rng.new(seed)
  let assert [p1_robot, ..p1_reserve] = p1_team
  let assert [p2_robot, ..p2_reserve] = p2_team
  let #(p1, seed) = combatant(config, p1_robot, p1_reserve, seed, now)
  let #(p2, seed) = combatant(config, p2_robot, p2_reserve, seed, now)
  Game(config:, p1:, p2:, seed:, status: Running, log: [Started])
}

/// A robot entering the battle: a fresh deck, table and starting energy.
fn combatant(
  config: Config,
  bot: Robot,
  reserve: List(Robot),
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
  Combatant(robot: bot, deck:, table: [], discard: [], energy:, reserve:)
  |> fill_table(config.table_size, seed, now)
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

/// Bring every table value up to date at `now` (drones grow with time).
/// Everything that reads table values should look at a settled game.
pub fn settle(game: Game, now: Int) -> Game {
  let settle_side = fn(c: Combatant) {
    Combatant(..c, table: list.map(c.table, table.settle(_, now)))
  }
  Game(..game, p1: settle_side(game.p1), p2: settle_side(game.p2))
}

fn play(
  game: Game,
  side: Side,
  index: Int,
  now: Int,
) -> Result(Game, Rejection) {
  let game = settle(game, now)
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
  let #(game, targets, effect) = resolve(game, side, played, now)
  let #(refilled, seed) = case played.card.target {
    // A launched drone takes the slot of the card that launched it.
    card.Launch(drone) -> {
      let c = combatant_of(game, side)
      let #(before, after) = list.split(c.table, index)
      let table = list.flatten([before, [table.placed(drone, now)], after])
      #(Combatant(..c, table:), game.seed)
    }
    _ -> refill(combatant_of(game, side), index, game.seed, now)
  }
  Game(..game, seed:)
  |> put(side, refilled)
  |> log(Played(side, played.card, played.value, targets, effect))
  |> check_destroyed(now)
  |> Ok
}

// AIMING ----------------------------------------------------------------------

/// What a card would hit if played now (see `aims`).
pub type Aim {
  /// `side`'s robot: an attack with no drones in the way, or a Malfunction
  /// (its own robot).
  AimRobot(side: Side)
  /// Cards in `slots` of `side`'s table: all of them, or one picked at
  /// random when played.
  AimCards(side: Side, slots: List(Int), all: Bool)
  /// It launches a drone.
  AimLaunch
}

/// What playing card `index` of `side`'s table would hit at `now`, so a
/// player can see it before playing. Slots are indexes of the tables as
/// they stand. An empty list: it would hit nothing.
pub fn aims(game: Game, side: Side, index: Int, now: Int) -> List(Aim) {
  let game = settle(game, now)
  let own = combatant_of(game, side)
  let foe = combatant_of(game, other(side))
  case list.drop(own.table, index) {
    [] -> []
    [played, ..] -> {
      // The card leaves the table before it resolves: it can't aim at
      // itself. Indexes after it are shifted back to the table as it is.
      let rest =
        list.append(
          list.take(own.table, index),
          list.drop(own.table, index + 1),
        )
      let own_slots = fn(slots) {
        list.map(slots, fn(i) {
          case i >= index {
            True -> i + 1
            False -> i
          }
        })
      }
      let cards = fn(side, slots, scope) {
        case slots {
          [] -> []
          _ -> [
            AimCards(side, slots, case scope {
              card.All(_) -> True
              card.One(_) -> False
            }),
          ]
        }
      }
      let lower = lowered(_, played.value, game.config.defence_floor)
      case played.card.target {
        card.OpponentHp ->
          case
            list.index_map(foe.table, fn(s, i) { #(i, s) })
            |> list.filter(fn(pair) { table.is_drone(pair.1) })
            |> list.map(fn(pair) { pair.0 })
          {
            [] -> [AimRobot(other(side))]
            drones -> [AimCards(other(side), drones, False)]
          }
        card.Opponent(scope) ->
          cards(other(side), table.candidates(foe.table, scope, lower), scope)
        card.Self(scope) ->
          cards(
            side,
            own_slots(
              table.candidates(rest, scope, fn(s: Slot) {
                s.value +. played.value
              }),
            ),
            scope,
          )
        card.Both(scope) ->
          list.append(
            cards(other(side), table.candidates(foe.table, scope, lower), scope),
            cards(side, own_slots(table.candidates(rest, scope, lower)), scope),
          )
        card.Burn(_) ->
          case
            list.index_map(foe.table, fn(s, i) { #(i, s) })
            |> list.filter(fn(pair) { table.burnable(pair.1) })
            |> list.map(fn(pair) { pair.0 })
          {
            [] -> []
            slots -> [AimCards(other(side), slots, False)]
          }
        card.Launch(_) -> [AimLaunch]
        card.NoEffect -> []
        card.OwnHp -> [AimRobot(side)]
      }
    }
  }
}

/// Returns the new game, how many things were affected (1 for HP, else the
/// number of table cards), and the total amount actually changed.
fn resolve(
  game: Game,
  side: Side,
  played: Slot,
  now: Int,
) -> #(Game, Int, Float) {
  let value = played.value
  // Opponent lowers, Self raises; the scope says what.
  case played.card.target {
    card.OpponentHp -> attack(game, other(side), value, now)
    card.Opponent(scope) ->
      affect_table(
        game,
        other(side),
        scope,
        lowered(_, value, game.config.defence_floor),
        now,
      )
    card.Self(scope) ->
      affect_table(game, side, scope, fn(s: Slot) { s.value +. value }, now)
    card.Both(scope) -> {
      let lower = lowered(_, value, game.config.defence_floor)
      let #(game, foe_targets, foe_effect) =
        affect_table(game, other(side), scope, lower, now)
      let #(game, own_targets, own_effect) =
        affect_table(game, side, scope, lower, now)
      #(game, foe_targets + own_targets, foe_effect +. own_effect)
    }
    card.Launch(_) -> #(game, 1, 0.0)
    card.Burn(fire) -> burn(game, other(side), fire, now)
    card.NoEffect -> #(game, 0, 0.0)
    // Straight to the robot: its own drones don't shield it from itself.
    card.OwnHp -> map_robot(game, side, robot.take_damage(_, value))
  }
}

/// Burn a random card of `target`'s that was lowered to 0. It leaves the
/// match (not to the discard pile), and `fire` takes its slot. Fire costs at
/// least as much to clear as the burnt card did, so burning never makes a
/// dead slot cheaper to clear.
fn burn(game: Game, target: Side, fire: Card, now: Int) -> #(Game, Int, Float) {
  let c = combatant_of(game, target)
  let candidates =
    c.table
    |> list.index_map(fn(s, i) { #(i, s) })
    |> list.filter(fn(pair) { table.burnable(pair.1) })
  case candidates {
    [] -> #(game, 0, 0.0)
    _ -> {
      let #(pick, seed) = rng.int_below(game.seed, list.length(candidates))
      let assert Ok(#(index, burnt)) = list.drop(candidates, pick) |> list.first
      let table =
        list.index_map(c.table, fn(s, i) {
          case i == index {
            True ->
              table.placed(
                card.Card(..fire, cost: float.max(fire.cost, burnt.card.cost)),
                now,
              )
            False -> s
          }
        })
      let game =
        Game(..game, seed:)
        |> put(target, Combatant(..c, table:))
        |> log(Burned(target, burnt.card))
      #(game, 1, 0.0)
    }
  }
}

/// An attack on `target`: it hits a random one of their drones if they have
/// any (leftover damage is lost), otherwise the robot.
fn attack(
  game: Game,
  target: Side,
  value: Float,
  now: Int,
) -> #(Game, Int, Float) {
  let c = combatant_of(game, target)
  let drones =
    c.table
    |> list.index_map(fn(s, i) { #(i, s) })
    |> list.filter(fn(pair) { table.is_drone(pair.1) })
  case drones {
    [] -> map_robot(game, target, robot.take_damage(_, value))
    _ -> {
      let #(pick, seed) = rng.int_below(game.seed, list.length(drones))
      let assert Ok(#(index, drone)) = list.drop(drones, pick) |> list.first
      let damage = float.min(value, drone.value)
      let left = amount.subtract(drone.value, value)
      let destroyed = amount.is_zero(left)
      let game = Game(..game, seed:)
      let game = case destroyed {
        True -> remove_slot(game, target, index, now)
        False ->
          put(
            game,
            target,
            Combatant(
              ..c,
              table: list.index_map(c.table, fn(s, i) {
                case i == index {
                  True -> Slot(..s, value: left)
                  False -> s
                }
              }),
            ),
          )
      }
      let game = log(game, DroneHit(target, drone.card, damage, destroyed))
      #(game, 1, damage)
    }
  }
}

/// Take a card off `side`'s table (a destroyed drone: it leaves the game)
/// and refill that slot from the deck.
fn remove_slot(game: Game, side: Side, index: Int, now: Int) -> Game {
  let c = combatant_of(game, side)
  let #(before, after) = list.split(c.table, index)
  let c = Combatant(..c, table: list.append(before, list.drop(after, 1)))
  let #(c, seed) = refill(c, index, game.seed, now)
  Game(..game, seed:) |> put(side, c)
}

/// Drones lowered to 0 by a table effect are destroyed.
fn clear_destroyed_drones(game: Game, side: Side, now: Int) -> Game {
  let c = combatant_of(game, side)
  let dead =
    c.table
    |> list.index_map(fn(s, i) { #(i, s) })
    |> list.filter(fn(pair) {
      table.is_drone(pair.1) && amount.is_zero({ pair.1 }.value)
    })
    |> list.reverse
  // Highest index first, so earlier indexes stay valid.
  list.fold(dead, game, fn(game, pair) {
    remove_slot(game, side, pair.0, now)
    |> log(DroneDestroyed(side, { pair.1 }.card))
  })
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
  now: Int,
) -> #(Game, Int, Float) {
  let c = combatant_of(game, side)
  let #(table, targets, seed) = table.affect(c.table, scope, change, game.seed)
  let effect =
    list.zip(c.table, table)
    |> list.fold(0.0, fn(total, pair) {
      total +. float.absolute_value({ pair.1 }.value -. { pair.0 }.value)
    })
  let game =
    Game(..game, seed:)
    |> put(side, Combatant(..c, table:))
    |> clear_destroyed_drones(side, now)
  #(game, targets, effect)
}

// DRAWING ---------------------------------------------------------------------

/// Cards are drawn at `now`: a growing card starts growing when it's drawn.
fn fill_table(
  c: Combatant,
  size: Int,
  seed: Seed,
  now: Int,
) -> #(Combatant, Seed) {
  case list.length(c.table) < size {
    False -> #(c, seed)
    True ->
      case draw(c, seed) {
        Ok(#(card, c, seed)) ->
          Combatant(..c, table: list.append(c.table, [table.placed(card, now)]))
          |> fill_table(size, seed, now)
        Error(Nil) -> #(c, seed)
      }
  }
}

/// Draw into the slot that was just played, so other cards keep their places.
fn refill(
  c: Combatant,
  index: Int,
  seed: Seed,
  now: Int,
) -> #(Combatant, Seed) {
  case draw(c, seed) {
    Ok(#(card, c, seed)) -> {
      let #(before, after) = list.split(c.table, index)
      let table = list.flatten([before, [table.placed(card, now)], after])
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

/// A destroyed robot leaves; the next in reserve enters. The other side
/// keeps its HP, energy and table. A side with no robot left loses.
fn check_destroyed(game: Game, now: Int) -> Game {
  let game = game |> replace_destroyed(P2, now) |> replace_destroyed(P1, now)
  case robot.is_destroyed(game.p1.robot), robot.is_destroyed(game.p2.robot) {
    _, True -> Game(..game, status: Won(P1))
    True, False -> Game(..game, status: Won(P2))
    False, False -> game
  }
}

fn replace_destroyed(game: Game, side: Side, now: Int) -> Game {
  let c = combatant_of(game, side)
  case robot.is_destroyed(c.robot), c.reserve {
    False, _ -> game
    True, [] -> log(game, Destroyed(side))
    True, [next, ..reserve] -> {
      let #(fresh, seed) = combatant(game.config, next, reserve, game.seed, now)
      Game(..game, seed:)
      |> put(side, fresh)
      |> log(Destroyed(side))
      |> log(Entered(side, next))
    }
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
