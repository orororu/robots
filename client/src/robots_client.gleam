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
import robots_client/battle/prebattle.{view_prebattle}
import robots_client/battle/view.{view_battle, view_report} as _
import robots_client/common/browser
import robots_client/common/styles.{css}
import robots_client/garage/shop.{view_shop}
import robots_client/garage/view.{view_of} as _
import robots_client/garage/workshop.{view_workshop}
import robots_client/hangar/view.{HangarView, view_hangar} as _
import robots_client/map/over.{view_over}
import robots_client/map/view.{view_map} as _
import robots_client/menu/model.{Menu} as _
import robots_client/menu/view.{view_menu} as _
import robots_client/model.{
  type Model, type Msg, BattleMsg, Frame, GarageMsg, HangarMsg, KeyDown, MapMsg,
  MenuMsg, Model, frame_ms, new_model,
}
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
      menu: Some(Menu(
        saved: save.decode(browser.load_run()) |> option.from_result,
      )),
    )
  #(model, subscriptions)
}

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("screen")], [
    html.style([], css),
    html.pre([], [element.text(header(model))]),
    view_screen(model),
    html.pre([attribute.class("banner")], [
      element.text(case model.now < model.flash_until {
        True -> "! " <> model.flash
        False -> ""
      }),
    ]),
  ])
}

/// The screen for where the player is. A feature's screen sends its own
/// messages, wrapped here.
fn view_screen(model: Model) -> Element(Msg) {
  let garage = view_of(model.run, model.garage, model.scale)
  let combat = model.combat
  case model.menu, model.hangar, combat.report, combat.battle {
    Some(menu), _, _, _ ->
      view_menu(menu, model.profile) |> element.map(MenuMsg)
    _, Some(h), _, _ ->
      HangarView(profile: model.profile, hangar: h, scale: model.scale)
      |> view_hangar
      |> element.map(HangarMsg)
    _, _, Some(r), _ -> view_report(r, model.scale) |> element.map(BattleMsg)
    _, _, _, Some(b) ->
      view_battle(b, model.scale, model.now) |> element.map(BattleMsg)
    None, None, None, None ->
      case model.run.phase {
        state.Over ->
          view_over(model.run, model.journal, model.profile)
          |> element.map(MapMsg)
        state.Fighting(_) -> view_prebattle(garage, combat.order)
        state.Repairing(_) -> view_shop(garage) |> element.map(GarageMsg)
        state.Upgrading(_) -> view_workshop(garage) |> element.map(GarageMsg)
        state.Choosing ->
          view_map(model.run, model.journal, model.scale)
          |> element.map(MapMsg)
      }
  }
}

fn header(model: Model) -> String {
  use <- bool.lazy_guard(model.menu != None, fn() {
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
