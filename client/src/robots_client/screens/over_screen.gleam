//// The end of a run and what it pays out.

import gleam/int
import gleam/list
import gleam/string
import lustre/element.{type Element}
import lustre/element/html
import robots/meta/blueprint
import robots/meta/profile
import robots_client/components/ui.{button_class, text}
import robots_client/model.{type Model, type Msg, ToHangar}

pub fn view_over(model: Model) -> Element(Msg) {
  html.div([], [
    text("news", model.news),
    text(
      "foe",
      "THE RUN IS OVER. You reached level "
        <> int.to_string(model.run.level)
        <> ".",
    ),
    view_earnings(model),
    button_class(">>> To the hangar", "banner", ToHangar),
  ])
}

/// What the run that just ended pays out.
pub fn view_earnings(model: Model) -> Element(Msg) {
  let e = profile.earnings(model.profile, model.run)
  let lines =
    list.flatten([
      [
        "DATA · +"
        <> int.to_string(e.data)
        <> " (battles won, levels reached and scrap left)",
      ],
      case e.bonus {
        0 -> []
        b -> [
          "  +" <> int.to_string(b) <> " for beating a boss for the first time",
        ]
      },
      case e.found {
        [] -> []
        found -> [
          "BLUEPRINTS FOUND · "
          <> string.join(list.map(found, blueprint.describe), ", ")
          <> " · research them in the hangar",
        ]
      },
    ])
  text("ally", string.join(lines, "\n"))
}
