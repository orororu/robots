//// Runs on autopilot: prints a sample map per level, then plays whole runs
//// and reports how far they get.
////
//// The autopilot picks paths at random (but heads for a repair shop when
//// it has money to spend), fights every battle with the AI
//// (`brain.human` on both sides), healthiest robot first. At shops it
//// repairs what it can afford, buys a used robot when it can (selling
//// spares for it), and buys parts worth installing right away. After every
//// battle and shop it installs spares worth it (armor; other parts only on
//// a robot short of cards, never a dead card), swaps broken plates for
//// looted armor, and builds a robot
//// from a spare chassis when it has a weapon and a battery for it. It never
//// trades weapons, so it's still a floor for what a player can do. At a
//// workshop it upgrades its priciest installed component.
////
//// Run with `gleam run -m run`.

import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import robots/ai/brain
import robots/balance/simulation
import robots/construction/builder
import robots/construction/part
import robots/construction/wear
import robots/content/enemies
import robots/rules/game
import robots/rules/rng.{type Seed}
import robots/run/map.{type Map}
import robots/run/price
import robots/run/shop
import robots/run/state.{type Run}
import robots/run/upgrade

const runs = 100

/// Enough money to make a detour to a repair shop worth it.
const shop_money = 20

/// Stop after beating this level's boss.
const last_level = 3

pub fn main() -> Nil {
  list.each([1, 2, 3], fn(level) {
    let #(m, _) = map.generate(level, rng.new(level))
    print_map(m)
  })
  io.println(
    "AUTOPILOT RUNS ("
    <> int.to_string(runs)
    <> ", random paths, buys at shops and builds robots)",
  )
  let results =
    list.map(int.range(1, runs + 1, [], list.prepend), fn(seed) {
      play(state.new(seed), rng.new(seed), 0, [], Team(gained: 0, most: 1))
    })
  report(results)
}

// MAP -------------------------------------------------------------------------

fn print_map(m: Map) -> Nil {
  io.println("LEVEL " <> int.to_string(m.level) <> " MAP")
  list.each(int.range(0, map.rows + 1, [], list.prepend) |> list.reverse, fn(r) {
    let row =
      map.row(m, r)
      |> list.map(fn(n) {
        int.to_string(n.id)
        <> " "
        <> event_text(n.event)
        <> case n.next {
          [] -> ""
          next -> " → " <> string.join(list.map(next, int.to_string), ",")
        }
      })
      |> string.join("  |  ")
    io.println("  " <> int.to_string(r) <> ": " <> row)
  })
  io.println("")
}

fn event_text(event: map.Event) -> String {
  case event {
    map.RepairShop -> "[repair]"
    map.Workshop -> "[workshop]"
    map.Battle(tier: map.Normal, enemy:) -> enemy.name
    map.Battle(tier: map.Strong, enemy:) -> "STRONG " <> enemy.name
    map.Battle(tier: map.Boss, enemy:) -> "BOSS " <> enemy.name
  }
}

// AUTOPILOT -------------------------------------------------------------------

type Ending {
  Ending(
    level: Int,
    row: Int,
    won: Bool,
    battles: Int,
    money: Int,
    /// The most robots owned at once, and robots bought or built.
    robots: Int,
    gained: Int,
    /// Who ended the run, e.g. "STRONG Firebug (Strong rapid firebug)".
    killer: String,
  )
}

/// Robots bought or built during the run, and the most owned at once.
type Team {
  Team(gained: Int, most: Int)
}

/// Count the robots `after` has beyond `before`'s.
fn count(team: Team, before: Run, after: Run) -> Team {
  let n = list.length(after.robots)
  Team(
    gained: team.gained + int.max(0, n - list.length(before.robots)),
    most: int.max(team.most, n),
  )
}

type Fight {
  Fight(tier: map.Tier, won: Bool)
}

fn play(
  run: Run,
  seed: Seed,
  battles: Int,
  fights: List(Fight),
  team: Team,
) -> #(Ending, List(Fight)) {
  case run.phase {
    _ if run.level > last_level -> #(
      ending(run, True, battles, "", team),
      fights,
    )
    state.Over -> #(ending(run, False, battles, last_enemy(run), team), fights)
    state.Choosing -> {
      // Like a player: with money to spend, head for a repair shop when
      // one is on offer; otherwise any way on.
      let options = state.choices(run)
      let shops = list.filter(options, fn(n) { n.event == map.RepairShop })
      let options = case shops, run.money >= shop_money {
        [_, ..], True -> shops
        _, _ -> options
      }
      let #(i, seed) = rng.int_below(seed, list.length(options))
      let assert [pick, ..] = list.drop(options, i)
      let assert Ok(run) = state.go(run, pick.id)
      play(run, seed, battles, fights, team)
    }
    state.Repairing(_) -> {
      let run =
        list.index_fold(run.robots, run, fn(run, bot, i) {
          case state.repair(run, i) {
            Ok(repaired) -> repaired
            // Can't afford it all: repair what it can, part by part (plates
            // first, they take the damage), then the chassis.
            Error(_) ->
              list.index_map(bot.parts, fn(_, j) { state.RepairPart(i, j) })
              |> list.append([state.RepairChassis(i)])
              |> list.fold(run, fn(run, target) {
                case state.repair_one(run, target) {
                  Ok(repaired) -> repaired
                  Error(_) -> run
                }
              })
          }
        })
      let shopped = run |> shop_for_robot |> shop_for_parts |> improve
      let team = count(team, run, shopped)
      let assert Ok(run) = state.leave(shopped)
      play(run, seed, battles, fights, team)
    }
    state.Upgrading(_) -> {
      let run = case best_upgrade(run) {
        Ok(target) ->
          case state.upgrade(run, target) {
            Ok(#(upgraded, _)) -> upgraded
            Error(_) -> run
          }
        Error(Nil) -> run
      }
      let run = case run.phase {
        state.Upgrading(_) -> {
          let assert Ok(left) = state.leave(run)
          left
        }
        _ -> run
      }
      play(run, seed, battles, fights, team)
    }
    state.Fighting(_) -> {
      let assert Ok(#(tier, enemy)) = state.battle(run)
      let order = battle_order(run)
      let assert Ok(squad) = state.team(run, order)
      let #(battle_seed, seed) = rng.next(seed)
      let final =
        simulation.teams(
          game.default_config(),
          squad,
          [enemies.robot(enemy)],
          battle_seed,
          brain.human,
        )
      let outcome = state.outcome(final, list.length(squad))
      let assert Ok(#(run, _)) = state.finish(run, order, outcome)
      let improved = improve(run)
      play(
        improved,
        seed,
        battles + 1,
        [Fight(tier, outcome.won), ..fights],
        count(team, run, improved),
      )
    }
  }
}

/// Healthiest robot first.
fn battle_order(run: Run) -> List(Int) {
  run.robots
  |> list.index_map(fn(bot, i) {
    let hp = case state.build(bot) {
      Ok(r) -> r.hp
      Error(_) -> 0.0
    }
    #(i, hp)
  })
  |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
  |> list.map(fn(pair) { pair.0 })
}

// SHOPPING AND THE GARAGE ------------------------------------------------------

/// The installed component most worth upgrading: the priciest one that can
/// still be upgraded (weapons usually), on any robot.
fn best_upgrade(run: Run) -> Result(state.Target, Nil) {
  run.robots
  |> list.index_map(fn(bot, r) {
    list.index_map(bot.parts, fn(p, i) { #(state.Installed(r, i), p) })
  })
  |> list.flatten
  |> list.filter(fn(pair) { upgrade.can_upgrade(pair.1) })
  |> list.sort(fn(a, b) { int.compare(price.of(b.1), price.of(a.1)) })
  |> list.first
  |> result.map(fn(pair) { pair.0 })
}

/// Buy the used robot on sale, selling spares first if money is short and
/// their sale makes up the difference.
fn shop_for_robot(run: Run) -> Run {
  case run.shop.robots {
    [offer, ..] -> {
      let cost = shop.robot_price(offer)
      let run = sell_until(run, cost)
      case state.buy_robot(run, 0) {
        Ok(bought) -> bought
        Error(_) -> run
      }
    }
    [] -> run
  }
}

/// Sell the cheapest spares until money reaches `target`, but only if
/// selling them all would.
fn sell_until(run: Run, target: Int) -> Run {
  case run.money >= target || state.budget(run) < target {
    True -> run
    False -> {
      let cheapest =
        run.parts
        |> list.index_map(fn(p, i) { #(i, price.sell(p)) })
        |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
      case cheapest {
        [#(i, _), ..] ->
          case state.sell(run, i) {
            Ok(sold) -> sell_until(sold, target)
            Error(_) -> run
          }
        [] -> run
      }
    }
  }
}

/// Buy each shop part that one of the robots can install right away.
fn shop_for_parts(run: Run) -> Run {
  list.fold(list.reverse(run.shop.parts), run, fn(run, p) {
    let usable =
      list.index_map(run.robots, fn(bot, _) { bot })
      |> list.any(worth(_, p))
    case
      usable,
      list.index_map(run.shop.parts, fn(q, i) { #(i, q) })
      |> list.find(fn(pair) { pair.1 == p })
    {
      True, Ok(#(i, _)) ->
        case state.buy_part(run, i) {
          Ok(bought) -> improve(bought)
          Error(_) -> run
        }
      _, _ -> run
    }
  })
}

/// Legal, with no dead or unaffordable cards.
fn fits(bot: state.Bot) -> Bool {
  case state.build(bot) {
    Ok(robot) -> builder.warnings(robot) == []
    Error(_) -> False
  }
}

/// Worth installing `p` on `bot`: armor always (more HP); other parts only
/// while the deck is short and they'd replace Malfunctions (extra cards
/// dilute a full deck: a second Buckler made the Tinker much weaker).
fn worth(bot: state.Bot, p: part.Component) -> Bool {
  let short = builder.malfunction_count(bot.chassis, bot.parts) > 0
  { p.kind == part.Armor || short }
  && !wear.is_broken(p)
  && fits(state.Bot(..bot, parts: [p, ..bot.parts]))
}

/// Install every spare worth it (see `worth`), build robots from spare chassis,
/// and swap broken plates for good ones.
fn improve(run: Run) -> Run {
  run |> install_spares |> assemble_spares |> refit
}

fn install_spares(run: Run) -> Run {
  let attempt =
    run.robots
    |> list.index_map(fn(bot, r) { #(r, bot) })
    |> list.find_map(fn(pair) {
      let #(r, bot) = pair
      run.parts
      |> list.index_map(fn(p, j) { #(j, p) })
      |> list.find_map(fn(spare) {
        let #(j, p) = spare
        case worth(bot, p) {
          True -> state.install(run, r, j)
          False -> Error(state.NoSuchPart)
        }
        |> result_nil
      })
    })
  case attempt {
    Ok(installed) -> install_spares(installed)
    Error(Nil) -> run
  }
}

fn result_nil(r: Result(a, e)) -> Result(a, Nil) {
  case r {
    Ok(x) -> Ok(x)
    Error(_) -> Error(Nil)
  }
}

/// Build a robot from the first spare chassis that the spares can arm:
/// a weapon that fits it and a battery; then the rest fills in through
/// `install_spares`.
fn assemble_spares(run: Run) -> Run {
  case run.chassis {
    [chassis, ..] -> {
      let spares = list.index_map(run.parts, fn(p, i) { #(i, p) })
      let weapons = list.filter(spares, fn(s) { { s.1 }.kind == part.Weapon })
      let batteries =
        list.filter(spares, fn(s) { { s.1 }.kind == part.Battery })
      let pick =
        list.find_map(weapons, fn(w) {
          list.find_map(batteries, fn(b) {
            case builder.build("", chassis, [w.1, b.1]) {
              Ok(_) -> Ok([w.0, b.0])
              Error(_) -> Error(Nil)
            }
          })
        })
      case pick {
        Ok(indexes) -> {
          let name = "Robot " <> int.to_string(list.length(run.robots) + 1)
          case state.assemble(run, name, 0, indexes) {
            Ok(built) -> install_spares(built)
            Error(_) -> run
          }
        }
        Error(Nil) -> run
      }
    }
    [] -> run
  }
}

/// Swap each broken plate for the first spare plate that fits.
fn refit(run: Run) -> Run {
  list.index_fold(run.robots, run, fn(run, _, r) {
    let assert [bot, ..] = list.drop(run.robots, r)
    list.index_fold(bot.parts, run, fn(run, p, i) {
      case wear.is_broken(p) {
        False -> run
        True ->
          list.index_fold(run.parts, Error(Nil), fn(found, spare, j) {
            case found, spare.kind, part.remaining_hp(spare) >. 0.0 {
              Error(Nil), part.Armor, True ->
                case state.swap(run, r, i, j) {
                  Ok(swapped) -> Ok(swapped)
                  Error(_) -> Error(Nil)
                }
              _, _, _ -> found
            }
          })
          |> fn(found) {
            case found {
              Ok(swapped) -> swapped
              Error(Nil) -> run
            }
          }
      }
    })
  })
}

fn ending(
  run: Run,
  won: Bool,
  battles: Int,
  killer: String,
  team: Team,
) -> Ending {
  let row = case run.at {
    Some(id) ->
      case map.node(run.map, id) {
        Ok(n) -> n.row
        Error(Nil) -> 0
      }
    _ -> 0
  }
  Ending(
    level: run.level,
    row:,
    won:,
    battles:,
    money: run.money,
    robots: team.most,
    gained: team.gained,
    killer:,
  )
}

fn last_enemy(run: Run) -> String {
  case run.at {
    Some(id) ->
      case map.node(run.map, id) {
        Ok(map.Node(event: map.Battle(tier:, enemy:), ..)) ->
          case tier {
            map.Normal -> ""
            map.Strong -> "STRONG "
            map.Boss -> "BOSS "
          }
          <> roster_name(enemy)
        _ -> "?"
      }
    _ -> "?"
  }
}

/// The roster name ("Rusty brawler") of a spawned enemy, whose own name
/// comes from its attributes.
fn roster_name(enemy: enemies.Enemy) -> String {
  enemies.levels()
  |> list.flat_map(fn(l) { [l.boss, ..list.append(l.enemies, l.strong)] })
  |> list.find(fn(e) { e.description == enemy.description })
  |> fn(found) {
    case found {
      Ok(e) -> e.name
      Error(Nil) -> enemy.name
    }
  }
}

// REPORT ----------------------------------------------------------------------

fn report(results: List(#(Ending, List(Fight)))) -> Nil {
  let total = int.to_float(list.length(results))
  let finished = list.map(results, fn(pair) { pair.0 })
  let fights = list.flat_map(results, fn(pair) { pair.1 })
  let wins = list.count(finished, fn(r) { r.won })
  io.println(
    "  completed all "
    <> int.to_string(last_level)
    <> " levels: "
    <> pct(int.to_float(wins) /. total),
  )
  list.each(
    int.range(1, last_level + 1, [], list.prepend) |> list.reverse,
    fn(level) {
      let reached = list.count(finished, fn(r) { r.level >= level })
      io.println(
        "  reached level "
        <> int.to_string(level)
        <> ": "
        <> pct(int.to_float(reached) /. total),
      )
    },
  )
  let battles = list.map(finished, fn(r) { int.to_float(r.battles) })
  io.println(
    "  battles per run: "
    <> float.to_string(float.to_precision(float.sum(battles) /. total, 1)),
  )
  let money = list.map(finished, fn(r) { int.to_float(r.money) })
  io.println(
    "  money left at the end: "
    <> int.to_string(float.round(float.sum(money) /. total))
    <> " (average)",
  )
  let average = fn(f: fn(Ending) -> Int) {
    float.to_string(float.to_precision(
      int.to_float(int.sum(list.map(finished, f))) /. total,
      1,
    ))
  }
  io.println(
    "  robots bought or built per run: "
    <> average(fn(r) { r.gained })
    <> " · most robots at once: "
    <> average(fn(r) { r.robots })
    <> " (average) · runs that had 2+ robots: "
    <> pct(int.to_float(list.count(finished, fn(r) { r.robots >= 2 })) /. total),
  )
  list.each([map.Normal, map.Strong, map.Boss], fn(tier) {
    let of_tier = list.filter(fights, fn(f) { f.tier == tier })
    let won = list.count(of_tier, fn(f) { f.won })
    case of_tier {
      [] -> Nil
      _ ->
        io.println(
          "  "
          <> string.pad_end(map.tier_name(tier) <> " battles won:", 26, " ")
          <> pct(int.to_float(won) /. int.to_float(list.length(of_tier)))
          <> " of "
          <> int.to_string(list.length(of_tier)),
        )
    }
  })
  io.println("  runs ended by:")
  finished
  |> list.filter(fn(r) { !r.won })
  |> list.map(fn(r) { "L" <> int.to_string(r.level) <> " " <> r.killer })
  |> list.group(fn(x) { x })
  |> dict_counts
  |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
  |> list.each(fn(pair) {
    io.println(
      "    " <> string.pad_end(pair.0, 44, " ") <> int.to_string(pair.1),
    )
  })
}

fn dict_counts(
  groups: dict.Dict(String, List(String)),
) -> List(#(String, Int)) {
  groups
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, list.length(pair.1)) })
}

fn pct(x: Float) -> String {
  int.to_string(float.round(x *. 100.0)) <> "%"
}
