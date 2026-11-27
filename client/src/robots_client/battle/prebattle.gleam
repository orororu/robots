//// Before a battle: the enemy, the battle order, Fight, and the garage.

import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import robots/content/enemies
import robots/rules/scale
import robots/run/map
import robots/run/state
import robots_client/battle/model.{Fight, First} as _
import robots_client/common/ui.{button, button_class, text}
import robots_client/common/wording.{bot_line}
import robots_client/garage/view.{type GarageView, view_garage}
import robots_client/model.{type Msg, BattleMsg, GarageMsg}

pub fn view_prebattle(g: GarageView, order: List(Int)) -> Element(Msg) {
  case state.battle(g.run) {
    Error(_) -> text("", "")
    Ok(#(tier, enemy)) -> {
      let foe = enemies.robot(enemy)
      html.div([], [
        text(
          "foe",
          string.uppercase(map.tier_name(tier))
            <> ": "
            <> enemy.name
            <> " ("
            <> enemy.chassis.name
            <> ", "
            <> int.to_string(scale.value(g.scale, foe.hp))
            <> " HP)\n  "
            <> enemy.description,
        ),
        text("", "BATTLE ORDER (click a robot to send it in first)"),
        html.div(
          [attribute.class("table")],
          list.index_map(order, fn(i, n) {
            let assert [bot, ..] = list.drop(g.run.robots, i)
            button(
              int.to_string(n + 1) <> ". " <> bot_line(g.scale, bot),
              BattleMsg(First(i)),
            )
          }),
        ),
        button_class(">>> FIGHT!", "banner", BattleMsg(Fight)),
        element.map(view_garage(g), GarageMsg),
      ])
    }
  }
}
