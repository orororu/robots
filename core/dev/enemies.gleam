//// Enemy roster report: each enemy against the starter robots.
////
////     cd core && gleam run -m enemies

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

const matches_per_seating = 30

pub fn main() -> Nil {
  io.println("ENEMY ROSTER · starter win rate against each enemy")
  io.println("  " <> string.pad_end("enemy", 30, " ") <> "Tinker  Scrapper")
  list.each(enemies.levels(), fn(l) {
    io.println("\n== Level " <> int.to_string(l.level))
    list.each(l.enemies, row(_, ""))
    list.each(l.strong, row(_, "strong "))
    row(l.boss, "BOSS ")
  })
}

fn row(enemy: Enemy, label: String) -> Nil {
  let foe = enemies.robot(enemy)
  io.println(
    "  "
    <> string.pad_end(label <> enemy.name, 30, " ")
    <> string.pad_start(win_rate(starters.tinker(), foe), 6, " ")
    <> string.pad_start(win_rate(starters.scrapper(), foe), 10, " "),
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
