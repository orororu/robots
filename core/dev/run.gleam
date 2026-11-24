//// Runs on autopilot: prints a sample map per level, then plays whole runs
//// and reports how far they get.
////
//// The autopilot picks paths at random (but heads for a repair shop when
//// it has money to spend), fights every battle with the AI
//// (`brain.human` on both sides), repairs at shops what it can afford,
//// and swaps broken plates for looted armor. It never buys, builds new
//// robots or changes weapons, so it's a floor for what a player can do.
////
//// Run with `gleam run -m run`.

import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/string
import robots/ai/brain
import robots/balance/simulation
import robots/construction/part
import robots/construction/wear
import robots/content/enemies
import robots/rules/game
import robots/rules/rng.{type Seed}
import robots/run/map.{type Map}
import robots/run/state.{type Run}

const runs = 40

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
    "AUTOPILOT RUNS (" <> int.to_string(runs) <> ", starter only, random paths)",
  )
  let results =
    list.map(int.range(1, runs + 1, [], list.prepend), fn(seed) {
      play(state.new(seed), rng.new(seed), 0, [])
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
    /// Who ended the run, e.g. "STRONG Firebug (Strong rapid firebug)".
    killer: String,
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
) -> #(Ending, List(Fight)) {
  case run.phase {
    _ if run.level > last_level -> #(ending(run, True, battles, ""), fights)
    state.Over -> #(ending(run, False, battles, last_enemy(run)), fights)
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
      play(run, seed, battles, fights)
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
      let assert Ok(run) = state.leave(run)
      play(run, seed, battles, fights)
    }
    state.Fighting(_) -> {
      let assert Ok(#(tier, enemy)) = state.battle(run)
      let order =
        int.range(0, list.length(run.robots), [], list.prepend) |> list.reverse
      let assert Ok(team) = state.team(run, order)
      let #(battle_seed, seed) = rng.next(seed)
      let final =
        simulation.teams(
          game.default_config(),
          team,
          [enemies.robot(enemy)],
          battle_seed,
          brain.human,
        )
      let outcome = state.outcome(final, list.length(team))
      let assert Ok(#(run, _)) = state.finish(run, order, outcome)
      play(refit(run), seed, battles + 1, [Fight(tier, outcome.won), ..fights])
    }
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

fn ending(run: Run, won: Bool, battles: Int, killer: String) -> Ending {
  let row = case run.at {
    Some(id) ->
      case map.node(run.map, id) {
        Ok(n) -> n.row
        Error(Nil) -> 0
      }
    _ -> 0
  }
  Ending(level: run.level, row:, won:, battles:, money: run.money, killer:)
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
