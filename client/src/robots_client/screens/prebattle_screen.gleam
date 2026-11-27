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
import robots_client/components/garage.{view_garage}
import robots_client/components/ui.{button, button_class, text}
import robots_client/model.{type Model, type Msg, Fight, First}
import robots_client/wording.{bot_line}

pub fn view_prebattle(model: Model) -> Element(Msg) {
  case state.battle(model.run) {
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
            <> int.to_string(scale.value(model.scale, foe.hp))
            <> " HP)\n  "
            <> enemy.description,
        ),
        text("", "BATTLE ORDER (click a robot to send it in first)"),
        html.div(
          [attribute.class("table")],
          list.index_map(model.order, fn(i, n) {
            let assert [bot, ..] = list.drop(model.run.robots, i)
            button(
              int.to_string(n + 1) <> ". " <> bot_line(model.scale, bot),
              First(i),
            )
          }),
        ),
        button_class(">>> FIGHT!", "banner", Fight),
        view_garage(garage.from_model(model)),
      ])
    }
  }
}
