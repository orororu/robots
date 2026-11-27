//// The battle and the report after it.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element.{type Element}
import lustre/element/html
import robots/meta/blueprint
import robots/rules/scale
import robots_client/components/battle_view
import robots_client/components/ui.{button_class, text}
import robots_client/model.{type Battle, type Model, type Msg, Continue, Play}
import robots_client/wording.{part_line}

pub fn view_battle(model: Model, b: Battle) -> Element(Msg) {
  let banner = text("dim", "[1-9] play a card")
  battle_view.view(b.game, model.scale, model.now, banner, Play)
}

pub fn view_report(model: Model) -> Element(Msg) {
  let assert Some(r) = model.report
  let s = model.scale
  let hp = fn(x) { int.to_string(scale.value(s, x)) }
  let robots =
    list.map(r.robots, fn(entry) {
      let #(name, before, after, max) = entry
      "  "
      <> string.pad_end(name, 12, " ")
      <> battle_view.bar(after, max, 20)
      <> " "
      <> hp(before)
      <> " → "
      <> case after >. 0.0 {
        True -> hp(after) <> "/" <> hp(max)
        False -> "DESTROYED (lost with its parts)"
      }
    })
  let loot =
    list.map(r.reward.parts, fn(p) { "  + " <> part_line(s, p) })
    |> list.append(case r.reward.chassis {
      Some(c) -> ["  + " <> c.name <> " chassis"]
      None -> []
    })
    |> list.append(case r.reward.blueprint {
      Some(b) -> [
        "  + Blueprint: "
        <> blueprint.describe(b)
        <> " (research it in the hangar after the run)",
      ]
      None -> []
    })
  html.div([], [
    text(
      case r.won {
        True -> "banner big"
        False -> "foe big"
      },
      case r.won {
        True -> "VICTORY"
        False -> "DEFEAT"
      }
        <> " against "
        <> r.enemy
        <> " · "
        <> int.to_string(r.seconds)
        <> " s",
    ),
    text(
      "ally",
      "YOUR ROBOTS (HP before → after)\n" <> string.join(robots, "\n"),
    ),
    text(
      "foe",
      "ENEMY  "
        <> battle_view.bar(r.enemy_hp, r.enemy_max_hp, 20)
        <> " "
        <> hp(r.enemy_hp)
        <> "/"
        <> hp(r.enemy_max_hp),
    ),
    case r.won {
      True ->
        text(
          "",
          "REWARD: +"
            <> int.to_string(r.reward.money)
            <> " scrap\n"
            <> string.join(loot, "\n")
            <> case r.level_after > r.level_before {
            True ->
              "\n\nThe boss is beaten! On to level "
              <> int.to_string(r.level_after)
              <> "."
            False -> ""
          },
        )
      False -> text("foe", "Every robot is gone. The run is over.")
    },
    button_class(">>> Continue [Enter]", "banner", Continue),
  ])
}
