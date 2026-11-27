//// Text-mode browser client. This is the "imperative shell": it reads the
//// clock and the keyboard, feeds messages into the pure core, and renders.
//// Swapping this text view for sprites later doesn't touch the game rules.
////
//// A run (`robots/run/state`) drives the screens: the map with the garage,
//// the enemy and battle order before a battle, the battle, the repair shop,
//// and the end of the run.
////
//// The core works in relative amounts (1.0 = base). Every number shown here
//// goes through `robots/rules/scale`, so the whole game can be rescaled in one place.

import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import robots/meta/profile
import robots/run/save
import robots/run/state
import robots_client/browser
import robots_client/model.{
  type Model, type Msg, Frame, KeyDown, Model, frame_ms, new_model,
}
import robots_client/screens/battle_screen.{view_battle, view_report}
import robots_client/screens/hangar_screen.{view_hangar}
import robots_client/screens/map_screen.{view_map}
import robots_client/screens/menu_screen.{view_menu}
import robots_client/screens/over_screen.{view_over}
import robots_client/screens/prebattle_screen.{view_prebattle}
import robots_client/screens/shop_screen.{view_shop}
import robots_client/screens/workshop_screen.{view_workshop}
import robots_client/styles.{css}
import robots_client/update.{update}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_: Nil) -> #(Model, Effect(Msg)) {
  let subscriptions =
    effect.from(fn(dispatch) {
      browser.every(frame_ms, fn() { dispatch(Frame(browser.now())) })
      browser.on_keydown(fn(key) { dispatch(KeyDown(key)) })
    })
  let profile =
    profile.decode(browser.load_profile()) |> result.unwrap(profile.new())
  let model =
    Model(
      ..new_model(
        state.new(browser.random_seed()),
        profile,
        None,
        browser.now(),
      ),
      menu: True,
      saved: save.decode(browser.load_run()) |> option.from_result,
    )
  #(model, subscriptions)
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("screen")], [
    html.style([], css),
    html.pre([], [element.text(header(model))]),
    case model.battle, model.run.phase {
      _, _ if model.menu -> view_menu(model)
      _, _ if model.hangar != None -> view_hangar(model)
      _, _ if model.report != None -> view_report(model)
      Some(b), _ -> view_battle(model, b)
      None, state.Over -> view_over(model)
      None, state.Fighting(_) -> view_prebattle(model)
      None, state.Repairing(_) -> view_shop(model)
      None, state.Upgrading(_) -> view_workshop(model)
      None, state.Choosing -> view_map(model)
    },
    html.pre([attribute.class("banner")], [
      element.text(case model.now < model.flash_until {
        True -> "! " <> model.flash
        False -> ""
      }),
    ]),
  ])
}

fn header(model: Model) -> String {
  use <- bool.lazy_guard(model.menu, fn() {
    "ROBOTS · "
    <> int.to_string(model.profile.data)
    <> " Data · "
    <> int.to_string(model.profile.runs)
    <> case model.profile.runs {
      1 -> " run played"
      _ -> " runs played"
    }
  })
  use <- bool.lazy_guard(model.hangar != None, fn() {
    "ROBOTS · HANGAR · "
    <> int.to_string(model.profile.data)
    <> " Data · "
    <> int.to_string(model.profile.runs)
    <> case model.profile.runs {
      1 -> " run"
      _ -> " runs"
    }
  })
  "ROBOTS · level "
  <> int.to_string(model.run.level)
  <> " · "
  <> int.to_string(model.run.money)
  <> " scrap · "
  <> int.to_string(list.length(model.run.robots))
  <> " of "
  <> int.to_string(model.run.truck)
  <> " robots in the truck"
}
