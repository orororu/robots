//// A run in progress: the map, where the player is, their robots, spare
//// parts and chassis, money (see docs/RUN.md). Pure: every step takes a run
//// and returns a new one, or an error saying why the step isn't allowed.
////
//// The loop:
////
//// 1. `Choosing`: pick one of `choices` with `go`.
//// 2. A battle node (`Fighting`): `battle` tells who waits there. Pick the
////    order of your robots, get them built with `team`, play the battle
////    (`game.teams`), then report it with `finish`: damage goes on the
////    robots' parts, destroyed robots are lost, and a win pays out money and
////    loot. Beating the boss moves on to the next level's map.
//// 3. A repair shop (`Repairing`): `repair` robots for money, then `leave`.
//// 4. A workshop (`Upgrading`): `upgrade` one component for free, once,
////    or `leave`.
//// 5. When every robot is destroyed, the run is `Over`. It pays out
////    `data`, and the blueprints it `found` (see docs/META.md).
////
//// The truck carries at most `truck` robots: assembling or buying one more
//// fails with `TruckFull`. Spare parts and chassis are unlimited.
////
//// The garage (`install`, `uninstall`, `swap`, `assemble`) works at any time
//// except during an `Over` run; every change must leave a legal build.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import robots/construction/builder.{type BuildError, type Chassis}
import robots/construction/part.{type Component}
import robots/construction/robot.{type Robot}
import robots/construction/wear
import robots/content/components
import robots/content/enemies.{type Enemy}
import robots/content/starters
import robots/meta/blueprint.{type Blueprint}
import robots/rules/amount
import robots/rules/game.{type Game, P1, P2}
import robots/rules/rng.{type Seed}
import robots/run/loot
import robots/run/map.{type Map, type Node, type Tier}
import robots/run/price
import robots/run/shop.{type Shop, Shop}
import robots/run/upgrade.{type Change}

/// Money for winning a battle, by tier. Placeholders: about one cheap part
/// for an ordinary enemy (part prices run 13-57).
pub const money_normal = 20

pub const money_strong = 40

pub const money_boss = 100

pub const starting_money = 0

/// Parts a won battle drops, by tier: few, but worth having.
pub const drops_normal = 1

pub const drops_strong = 2

pub const drops_boss = 2

/// A robot the player owns, as the parts it's built from. It's assembled
/// into a fighting `Robot` for each battle.
pub type Bot {
  Bot(name: String, chassis: Chassis, parts: List(Component))
}

pub type Phase {
  /// Pick the next node from `choices`.
  Choosing
  /// At a battle node, before the battle is reported.
  Fighting(node: Int)
  /// At a repair shop.
  Repairing(node: Int)
  /// At a workshop, before the upgrade.
  Upgrading(node: Int)
  /// Every robot was destroyed.
  Over
}

pub type Run {
  Run(
    level: Int,
    map: Map,
    /// The node the player is at; `None` before the first step of a level.
    at: Option(Int),
    /// The nodes visited on this level, in order.
    path: List(Int),
    phase: Phase,
    robots: List(Bot),
    /// Spare parts and chassis, from loot.
    parts: List(Component),
    chassis: List(Chassis),
    money: Int,
    /// What the repair shop the player is at sells (empty elsewhere).
    shop: Shop,
    /// How many robots the truck carries.
    truck: Int,
    /// How many robots the player's fabricator builds (bosses can drop its
    /// upgrade while it's below the most).
    fabricator: Int,
    /// Each battle won, by tier, latest first.
    wins: List(Tier),
    /// Blueprints found in this run, in order.
    found: List(Blueprint),
    seed: Seed,
  )
}

/// What a won battle paid.
pub type Reward {
  Reward(
    money: Int,
    parts: List(Component),
    chassis: Option(Chassis),
    blueprint: Option(Blueprint),
  )
}

/// How a battle went for the player: whether they won, and each robot's HP
/// at the end, in battle order (0 for destroyed robots, untouched HP for
/// robots that never entered).
pub type Outcome {
  Outcome(won: Bool, hp_left: List(Float))
}

pub type Error {
  WrongPhase
  NotReachable(node: Int)
  /// A battle order must name every robot once.
  BadOrder
  NoSuchRobot
  NoSuchPart
  NoSuchChassis
  CantBuild(robot: String, errors: List(BuildError))
  NotEnoughMoney(price: Int, money: Int)
  /// The truck carries `robots` robots and is full.
  TruckFull(robots: Int)
  /// Every card of the component is at its best attribute already.
  CantUpgrade
}

/// A component to upgrade: installed on a robot, or a spare.
pub type Target {
  Installed(robot: Int, part: Int)
  Spare(part: Int)
}

/// Robots a truck carries without upgrades.
pub const default_truck = 2

/// A new run at level 1 with the Tinker, a default truck and no blueprints.
pub fn new(seed: Int) -> Run {
  start(
    seed,
    [Bot("Tinker", components.frame(), starters.tinker_parts())],
    default_truck,
    1,
  )
}

/// A new run at level 1 with these robots (the fabricator's) and a truck
/// for `truck` robots; the player's fabricator builds `fabricator`.
pub fn start(seed: Int, robots: List(Bot), truck: Int, fabricator: Int) -> Run {
  let seed = rng.new(seed)
  let #(map, seed) = map.generate(1, seed)
  Run(
    level: 1,
    map:,
    at: None,
    path: [],
    phase: Choosing,
    robots:,
    parts: [],
    chassis: [],
    money: starting_money,
    shop: shop.empty,
    truck:,
    fabricator:,
    wins: [],
    found: [],
    seed:,
  )
}

// DATA -------------------------------------------------------------------------

pub const data_normal = 1

pub const data_strong = 3

pub const data_boss = 10

/// For each level reached past the first.
pub const data_level = 5

/// Scrap left at the end, per Data.
pub const scrap_per_data = 20

/// What the run has earned so far, in Data: its wins, the levels it
/// reached and the scrap it holds. Paid out when it's over.
pub fn data(run: Run) -> Int {
  let wins =
    list.map(run.wins, fn(tier) {
      case tier {
        map.Normal -> data_normal
        map.Strong -> data_strong
        map.Boss -> data_boss
      }
    })
    |> int.sum
  wins + { run.level - 1 } * data_level + run.money / scrap_per_data
}

// THE MAP ---------------------------------------------------------------------

/// The nodes the player can move to next.
pub fn choices(run: Run) -> List(Node) {
  case run.phase, run.at {
    Choosing, None -> map.start(run.map)
    Choosing, Some(id) ->
      case map.node(run.map, id) {
        Ok(node) -> map.next(run.map, node)
        Error(Nil) -> []
      }
    _, _ -> []
  }
}

pub fn go(run: Run, id: Int) -> Result(Run, Error) {
  use <- require(run.phase == Choosing, WrongPhase)
  case list.find(choices(run), fn(n) { n.id == id }) {
    Error(Nil) -> Error(NotReachable(id))
    Ok(node) -> {
      let run = Run(..run, at: Some(id), path: list.append(run.path, [id]))
      case node.event {
        map.Battle(..) -> Ok(Run(..run, phase: Fighting(id)))
        map.RepairShop -> {
          let #(stock, seed) = shop.stock(run.level, budget(run), run.seed)
          Ok(Run(..run, phase: Repairing(id), shop: stock, seed:))
        }
        map.Workshop -> Ok(Run(..run, phase: Upgrading(id)))
      }
    }
  }
}

/// The battle waiting at the current node.
pub fn battle(run: Run) -> Result(#(Tier, Enemy), Error) {
  case run.phase {
    Fighting(id) ->
      case map.node(run.map, id) {
        Ok(map.Node(event: map.Battle(tier:, enemy:), ..)) -> Ok(#(tier, enemy))
        _ -> Error(WrongPhase)
      }
    _ -> Error(WrongPhase)
  }
}

// BATTLES ---------------------------------------------------------------------

/// The player's robots built for battle, in `order` (indexes into
/// `run.robots`; every robot exactly once).
pub fn team(run: Run, order: List(Int)) -> Result(List(Robot), Error) {
  use <- require(run.phase != Over, WrongPhase)
  let all = int.range(0, list.length(run.robots), [], list.prepend)
  use <- require(list.sort(order, int.compare) == list.reverse(all), BadOrder)
  list.try_map(order, fn(i) {
    let assert [bot, ..] = list.drop(run.robots, i)
    build(bot)
  })
}

/// The player's side of a finished battle (`game.teams` with `team_size`
/// robots for P1).
pub fn outcome(state: Game, team_size: Int) -> Outcome {
  case state.status {
    game.Won(P2) -> Outcome(won: False, hp_left: list.repeat(0.0, team_size))
    status -> {
      let side = state.p1
      let destroyed = team_size - 1 - list.length(side.reserve)
      Outcome(
        won: status == game.Won(P1),
        hp_left: list.flatten([
          list.repeat(0.0, destroyed),
          [side.robot.hp],
          list.map(side.reserve, fn(r) { r.hp }),
        ]),
      )
    }
  }
}

/// Report the battle at the current node. Damage goes on the robots'
/// parts; destroyed robots are lost with their parts. A win pays money and
/// loot (`drops_normal`...; a chassis for a boss, which also moves the run
/// to the next level, and sometimes a cheap one for a strong enemy); a loss ends the run.
pub fn finish(
  run: Run,
  order: List(Int),
  outcome: Outcome,
) -> Result(#(Run, Reward), Error) {
  use #(tier, _) <- result.try(battle(run))
  use team <- result.try(team(run, order))
  use <- require(list.length(outcome.hp_left) == list.length(order), BadOrder)
  // Each robot's state after the battle, by its index in `run.robots`.
  let after =
    list.zip(order, list.zip(team, outcome.hp_left))
    |> list.map(fn(entry) {
      let #(i, #(fought, hp_left)) = entry
      let assert [bot, ..] = list.drop(run.robots, i)
      case amount.is_zero(hp_left) {
        True -> #(i, None)
        False -> {
          let damage = wear.taken(fought.hp, hp_left)
          let #(chassis, parts) = wear.assign(bot.chassis, bot.parts, damage)
          #(i, Some(Bot(..bot, chassis:, parts:)))
        }
      }
    })
  let robots =
    run.robots
    |> list.index_map(fn(bot, i) {
      case list.key_find(after, i) {
        Ok(changed) -> changed
        Error(Nil) -> Some(bot)
      }
    })
    |> option.values
  let run = Run(..run, robots:)
  case outcome.won, robots {
    False, _ | _, [] ->
      Ok(#(
        Run(..run, phase: Over),
        Reward(money: 0, parts: [], chassis: None, blueprint: None),
      ))
    True, _ -> Ok(reward(run, tier))
  }
}

fn reward(run: Run, tier: Tier) -> #(Run, Reward) {
  let money = case tier {
    map.Normal -> money_normal
    map.Strong -> money_strong
    map.Boss -> money_boss
  }
  let drops = case tier {
    map.Normal -> drops_normal
    map.Strong -> drops_strong
    map.Boss -> drops_boss
  }
  let #(parts, seed) = loot.rolls(run.level, drops, run.seed)
  let #(chassis, seed) = case tier {
    map.Boss -> {
      let #(c, seed) = loot.boss_chassis(run.level, seed)
      #(Some(c), seed)
    }
    map.Strong -> loot.strong_chassis(run.level, seed)
    map.Normal -> #(None, seed)
  }
  // A strong enemy's chassis drop is a wreck: it comes with a worn weapon
  // and battery, so it can be built at once.
  let #(parts, seed) = case tier, chassis {
    map.Strong, Some(c) -> {
      let #(wreck, seed) = loot.wreck(run.level, c, seed)
      #(list.append(parts, wreck), seed)
    }
    _, _ -> #(parts, seed)
  }
  let #(found, seed) = blueprint.roll(run.level, tier, run.fabricator, seed)
  let run =
    Run(
      ..run,
      phase: Choosing,
      money: run.money + money,
      parts: list.append(run.parts, parts),
      chassis: list.append(run.chassis, option.values([chassis])),
      wins: [tier, ..run.wins],
      found: list.append(run.found, option.values([found])),
      seed:,
    )
  let run = case tier {
    map.Boss -> next_level(run)
    _ -> run
  }
  #(run, Reward(money:, parts:, chassis:, blueprint: found))
}

fn next_level(run: Run) -> Run {
  let level = run.level + 1
  let #(map, seed) = map.generate(level, run.seed)
  Run(..run, level:, map:, at: None, path: [], seed:)
}

// REPAIR SHOP -----------------------------------------------------------------

/// One thing to repair at a repair shop.
pub type Repair {
  /// The chassis of robot `robot`.
  RepairChassis(robot: Int)
  /// Installed part `part` of robot `robot`.
  RepairPart(robot: Int, part: Int)
  /// Spare part `part`.
  RepairSpare(part: Int)
}

/// What it costs to repair one chassis or part, by its wear.
pub fn repair_one_price(run: Run, target: Repair) -> Result(Int, Error) {
  case target {
    RepairChassis(robot) -> {
      use bot <- result.try(robot_at(run, robot))
      Ok(price.repair(bot.chassis.wear))
    }
    RepairPart(robot, i) -> {
      use bot <- result.try(robot_at(run, robot))
      use p <- result.try(part_at(bot.parts, i))
      Ok(price.repair(part_wear(p)))
    }
    RepairSpare(i) -> {
      use p <- result.try(part_at(run.parts, i))
      Ok(price.repair(part_wear(p)))
    }
  }
}

/// Repair just one chassis or part.
pub fn repair_one(run: Run, target: Repair) -> Result(Run, Error) {
  use <- require(at_shop(run), WrongPhase)
  use cost <- result.try(repair_one_price(run, target))
  use <- require(cost <= run.money, NotEnoughMoney(cost, run.money))
  let run = Run(..run, money: run.money - cost)
  case target {
    RepairChassis(robot) -> {
      use bot <- result.try(robot_at(run, robot))
      let bot = Bot(..bot, chassis: wear.repair_chassis(bot.chassis))
      Ok(Run(..run, robots: replace(run.robots, robot, bot)))
    }
    RepairPart(robot, i) -> {
      use bot <- result.try(robot_at(run, robot))
      let bot =
        Bot(
          ..bot,
          parts: list.index_map(bot.parts, fn(p, j) {
            case i == j {
              True -> wear.repair_part(p)
              False -> p
            }
          }),
        )
      Ok(Run(..run, robots: replace(run.robots, robot, bot)))
    }
    RepairSpare(i) ->
      Ok(
        Run(
          ..run,
          parts: list.index_map(run.parts, fn(p, j) {
            case i == j {
              True -> wear.repair_part(p)
              False -> p
            }
          }),
        ),
      )
  }
}

/// Sell spare part `spare` to the shop for `price.sell`.
pub fn sell(run: Run, spare: Int) -> Result(Run, Error) {
  use <- require(at_shop(run), WrongPhase)
  use p <- result.try(part_at(run.parts, spare))
  Ok(
    Run(
      ..run,
      money: run.money + price.sell(p),
      parts: remove_at(run.parts, spare),
    ),
  )
}

fn at_shop(run: Run) -> Bool {
  case run.phase {
    Repairing(_) -> True
    _ -> False
  }
}

fn part_wear(p: Component) -> Float {
  case p.kind {
    part.Armor -> p.wear
    _ -> 0.0
  }
}

fn part_at(parts: List(Component), i: Int) -> Result(Component, Error) {
  case i >= 0 {
    True ->
      list.drop(parts, i) |> list.first |> result.replace_error(NoSuchPart)
    False -> Error(NoSuchPart)
  }
}

/// What it costs to repair a robot fully (its chassis and every plate).
pub fn repair_price(bot: Bot) -> Int {
  price.repair(wear.total(bot.chassis, bot.parts))
}

pub fn repair(run: Run, robot: Int) -> Result(Run, Error) {
  use <- require(
    case run.phase {
      Repairing(_) -> True
      _ -> False
    },
    WrongPhase,
  )
  use bot <- result.try(robot_at(run, robot))
  let cost = repair_price(bot)
  use <- require(cost <= run.money, NotEnoughMoney(cost, run.money))
  let #(chassis, parts) = wear.repair(bot.chassis, bot.parts)
  Ok(
    Run(
      ..run,
      money: run.money - cost,
      robots: replace(run.robots, robot, Bot(..bot, chassis:, parts:)),
    ),
  )
}

/// Leave the repair shop.
pub fn leave(run: Run) -> Result(Run, Error) {
  case run.phase {
    Repairing(_) -> Ok(Run(..run, phase: Choosing, shop: shop.empty))
    Upgrading(_) -> Ok(Run(..run, phase: Choosing))
    _ -> Error(WrongPhase)
  }
}

// THE WORKSHOP ----------------------------------------------------------------

/// The component at `target`.
pub fn target_part(run: Run, target: Target) -> Result(Component, Error) {
  case target {
    Installed(robot:, part:) -> {
      use bot <- result.try(robot_at(run, robot))
      part_at(bot.parts, part)
    }
    Spare(part:) -> part_at(run.parts, part)
  }
}

/// Upgrade the component at `target` (see `run/upgrade`): the workshop's
/// one upgrade, after which the player moves on. Returns the card changed.
pub fn upgrade(run: Run, target: Target) -> Result(#(Run, Change), Error) {
  use <- require(
    case run.phase {
      Upgrading(_) -> True
      _ -> False
    },
    WrongPhase,
  )
  use p <- result.try(target_part(run, target))
  use #(upgraded, change, seed) <- result.try(
    upgrade.apply(p, run.seed) |> result.replace_error(CantUpgrade),
  )
  let run = case target {
    Installed(robot:, part:) -> {
      let assert Ok(bot) = robot_at(run, robot)
      let bot = Bot(..bot, parts: replace(bot.parts, part, upgraded))
      Run(..run, robots: replace(run.robots, robot, bot))
    }
    Spare(part:) -> Run(..run, parts: replace(run.parts, part, upgraded))
  }
  Ok(#(Run(..run, phase: Choosing, seed:), change))
}

/// What the player could pay at a shop: their money plus what their spare
/// parts would sell for.
pub fn budget(run: Run) -> Int {
  run.money + int.sum(list.map(run.parts, price.sell))
}

/// Buy part `i` of the shop's stock: it goes to the spares.
pub fn buy_part(run: Run, i: Int) -> Result(Run, Error) {
  use <- require(at_shop(run), WrongPhase)
  use p <- result.try(part_at(run.shop.parts, i))
  use run <- result.try(pay(run, shop.part_price(p)))
  Ok(
    Run(
      ..run,
      parts: list.append(run.parts, [p]),
      shop: Shop(..run.shop, parts: remove_at(run.shop.parts, i)),
    ),
  )
}

/// Buy used robot `i`: it joins the team.
pub fn buy_robot(run: Run, i: Int) -> Result(Run, Error) {
  use <- require(at_shop(run), WrongPhase)
  use offer <- result.try(
    list.drop(run.shop.robots, i)
    |> list.first
    |> result.replace_error(NoSuchRobot),
  )
  use <- require(room_in_truck(run), TruckFull(run.truck))
  use run <- result.try(pay(run, shop.robot_price(offer)))
  let bot = Bot(name: offer.name, chassis: offer.chassis, parts: offer.parts)
  Ok(
    Run(
      ..run,
      robots: list.append(run.robots, [bot]),
      shop: Shop(..run.shop, robots: remove_at(run.shop.robots, i)),
    ),
  )
}

/// Whether the truck has room for one more robot.
pub fn room_in_truck(run: Run) -> Bool {
  list.length(run.robots) < run.truck
}

fn pay(run: Run, cost: Int) -> Result(Run, Error) {
  use <- require(cost <= run.money, NotEnoughMoney(cost, run.money))
  Ok(Run(..run, money: run.money - cost))
}

// GARAGE ----------------------------------------------------------------------

/// Install spare part `spare` on robot `robot`.
pub fn install(run: Run, robot: Int, spare: Int) -> Result(Run, Error) {
  swap_parts(run, robot, [], [spare])
}

/// Take installed part `installed` off robot `robot` into the spares.
pub fn uninstall(run: Run, robot: Int, installed: Int) -> Result(Run, Error) {
  swap_parts(run, robot, [installed], [])
}

/// Replace installed part `installed` with spare part `spare` in one step
/// (e.g. trading a weapon, which can't be uninstalled first).
pub fn swap(
  run: Run,
  robot: Int,
  installed: Int,
  spare: Int,
) -> Result(Run, Error) {
  swap_parts(run, robot, [installed], [spare])
}

/// Build a new robot from spare chassis `chassis` and spare parts `parts`.
pub fn assemble(
  run: Run,
  name: String,
  chassis: Int,
  parts: List(Int),
) -> Result(Run, Error) {
  use <- require(run.phase != Over, WrongPhase)
  use <- require(room_in_truck(run), TruckFull(run.truck))
  use frame <- result.try(
    list.drop(run.chassis, chassis)
    |> list.first
    |> result.replace_error(NoSuchChassis),
  )
  use #(taken, spares) <- result.try(take(run.parts, parts))
  let bot = Bot(name:, chassis: frame, parts: taken)
  use _ <- result.try(build(bot))
  Ok(
    Run(
      ..run,
      robots: list.append(run.robots, [bot]),
      parts: spares,
      chassis: remove_at(run.chassis, chassis),
    ),
  )
}

/// Move robot `robot` onto spare chassis `chassis`. It keeps every part
/// that fits (weapons first, then batteries, then the rest, each in its
/// order); the others become spares, and so does the old chassis. Refused
/// when what's left can't fight (no weapon or battery fits). Returns the
/// parts that came off.
pub fn rebuild(
  run: Run,
  robot: Int,
  chassis: Int,
) -> Result(#(Run, List(Component)), Error) {
  use <- require(run.phase != Over, WrongPhase)
  use bot <- result.try(robot_at(run, robot))
  use frame <- result.try(
    list.drop(run.chassis, chassis)
    |> list.first
    |> result.replace_error(NoSuchChassis),
  )
  let #(kept, dropped) = builder.fit(frame, bot.parts)
  let rebuilt = Bot(..bot, chassis: frame, parts: kept)
  use _ <- result.try(build(rebuilt))
  let robots =
    list.index_map(run.robots, fn(b, i) {
      case i == robot {
        True -> rebuilt
        False -> b
      }
    })
  Ok(#(
    Run(
      ..run,
      robots:,
      parts: list.append(run.parts, dropped),
      chassis: list.append(remove_at(run.chassis, chassis), [bot.chassis]),
    ),
    dropped,
  ))
}

fn swap_parts(
  run: Run,
  robot: Int,
  off: List(Int),
  on: List(Int),
) -> Result(Run, Error) {
  use <- require(run.phase != Over, WrongPhase)
  use bot <- result.try(robot_at(run, robot))
  use #(removed, kept) <- result.try(take(bot.parts, off))
  use #(added, spares) <- result.try(take(run.parts, on))
  let bot = Bot(..bot, parts: list.append(kept, added))
  use _ <- result.try(build(bot))
  Ok(
    Run(
      ..run,
      robots: replace(run.robots, robot, bot),
      parts: list.append(spares, removed),
    ),
  )
}

// HELPERS ---------------------------------------------------------------------

pub fn build(bot: Bot) -> Result(Robot, Error) {
  builder.build(bot.name, bot.chassis, bot.parts)
  |> result.map_error(CantBuild(bot.name, _))
}

fn robot_at(run: Run, i: Int) -> Result(Bot, Error) {
  case i >= 0 {
    True ->
      list.drop(run.robots, i)
      |> list.first
      |> result.replace_error(NoSuchRobot)
    False -> Error(NoSuchRobot)
  }
}

/// Split `items` into the ones at `indexes` (in that order) and the rest.
fn take(
  items: List(a),
  indexes: List(Int),
) -> Result(#(List(a), List(a)), Error) {
  let numbered = list.index_map(items, fn(x, i) { #(i, x) })
  use taken <- result.try(
    list.try_map(indexes, fn(i) {
      list.key_find(numbered, i) |> result.replace_error(NoSuchPart)
    }),
  )
  use <- require(
    list.length(list.unique(indexes)) == list.length(indexes),
    NoSuchPart,
  )
  let rest =
    numbered
    |> list.filter(fn(pair) { !list.contains(indexes, pair.0) })
    |> list.map(fn(pair) { pair.1 })
  Ok(#(taken, rest))
}

fn replace(items: List(a), at: Int, with: a) -> List(a) {
  list.index_map(items, fn(x, i) {
    case i == at {
      True -> with
      False -> x
    }
  })
}

fn remove_at(items: List(a), at: Int) -> List(a) {
  items
  |> list.index_map(fn(x, i) { #(i, x) })
  |> list.filter(fn(pair) { pair.0 != at })
  |> list.map(fn(pair) { pair.1 })
}

fn require(condition: Bool, error: Error, next: fn() -> Result(a, Error)) {
  case condition {
    True -> next()
    False -> Error(error)
  }
}
