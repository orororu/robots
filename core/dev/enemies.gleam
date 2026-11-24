//// Enemy roster report: each enemy against the starter robots, at full
//// strength and as met in a run (worn down by its condition, see
//// `enemies.spawn`), with how much HP the Tinker loses to it.
////
////     cd core && gleam run -m enemies

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import robots/ai/brain
import robots/balance/simulation
import robots/construction/robot.{type Robot}
import robots/content/enemies.{type Enemy}
import robots/content/starters
import robots/rules/game.{P1, P2, Won}
import robots/rules/rng
import robots/run/map

const matches_per_seating = 30

pub fn main() -> Nil {
  io.println("ENEMY ROSTER · starter win rate against each enemy")
  io.println(
    "  full: at full strength · met: worn down as met in a run · HP lost: the Tinker's, as met",
  )
  io.println(
    "  "
    <> string.pad_end("enemy", 30, " ")
    <> "Tinker  Scrapper    met  HP lost",
  )
  list.each(enemies.levels(), fn(l) {
    io.println("\n== Level " <> int.to_string(l.level))
    list.each(l.enemies, row(_, l.level, map.Normal, ""))
    list.each(l.strong, row(_, l.level, map.Strong, "strong "))
    row(l.boss, l.level, map.Boss, "BOSS ")
  })
}

fn row(enemy: Enemy, level: Int, tier: map.Tier, label: String) -> Nil {
  let foe = enemies.robot(enemy)
  let #(met_wins, lost) = as_met(enemy, level, tier)
  io.println(
    "  "
    <> string.pad_end(label <> enemy.name, 30, " ")
    <> string.pad_start(win_rate(starters.tinker(), foe), 6, " ")
    <> string.pad_start(win_rate(starters.scrapper(), foe), 10, " ")
    <> string.pad_start(met_wins, 7, " ")
    <> string.pad_start(lost, 9, " "),
  )
}

fn win_rate(me: Robot, foe: Robot) -> String {
  let config = game.default_config()
  let a = simulation.series(config, me, foe, matches_per_seating, brain.human)
  let b = simulation.series(config, foe, me, matches_per_seating, brain.human)
  let wins =
    list.count(a, fn(o) { o.status == Won(P1) })
    + list.count(b, fn(o) { o.status == Won(P2) })
  int.to_string(wins * 100 / { 2 * matches_per_seating }) <> "%"
}

/// The Tinker against this enemy as spawned in a run, a new spawn per match:
/// its win rate and the average share of its HP lost (all of it on a loss).
fn as_met(enemy: Enemy, level: Int, tier: map.Tier) -> #(String, String) {
  let tinker = starters.tinker()
  let n = 2 * matches_per_seating
  let results =
    int.range(0, n, [], list.prepend)
    |> list.map(fn(seed) {
      let #(spawned, _) =
        enemies.spawn(enemy, level, map.condition(level, tier), rng.new(seed))
      let g =
        simulation.teams(
          game.default_config(),
          [tinker],
          [enemies.robot(spawned)],
          seed,
          brain.human,
        )
      case g.status {
        Won(P1) -> #(True, { tinker.hp -. g.p1.robot.hp } /. tinker.max_hp)
        _ -> #(False, 1.0)
      }
    })
  let wins = list.count(results, fn(r) { r.0 })
  let lost = list.fold(results, 0.0, fn(sum, r) { sum +. r.1 })
  #(
    int.to_string(wins * 100 / n) <> "%",
    int.to_string(float.round(lost /. int.to_float(n) *. 100.0)) <> "%",
  )
}
