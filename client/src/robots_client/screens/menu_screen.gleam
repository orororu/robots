//// The start menu: continue the saved run or start a new one.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element.{type Element}
import lustre/element/html
import robots/meta/profile
import robots/run/state
import robots_client/components/ui.{button, button_class, text}
import robots_client/model.{type Model, type Msg, ContinueRun, NewGame}

pub fn view_menu(model: Model) -> Element(Msg) {
  let continue = case model.saved {
    Some(run) -> {
      let robots = run.robots |> list.map(fn(b) { b.name }) |> string.join(", ")
      let where = case run.phase {
        state.Over -> "over, not paid out yet"
        state.Fighting(_) -> "before a battle"
        state.Repairing(_) -> "at a repair shop"
        state.Upgrading(_) -> "at a workshop"
        state.Choosing -> "on the map"
      }
      [
        button_class(">>> Continue", "banner", ContinueRun),
        text(
          "dim",
          "    level "
            <> int.to_string(run.level)
            <> ", "
            <> where
            <> " · "
            <> case robots {
            "" -> "no robots left"
            _ -> robots
          }
            <> " · "
            <> int.to_string(run.money)
            <> " scrap · "
            <> int.to_string(list.length(run.wins))
            <> " battles won",
        ),
      ]
    }
    None -> [text("dim", "    Continue: no run in progress")]
  }
  let new = case model.saved {
    Some(run) -> {
      let e = profile.earnings(model.profile, run)
      button(
        ">>> New run · abandons the current one (it pays "
          <> int.to_string(e.data + e.bonus)
          <> " Data, as if lost)",
        NewGame,
      )
    }
    None -> button_class(">>> New run", "banner", NewGame)
  }
  html.div([], [text("", "MENU"), ..list.append(continue, [new])])
}
