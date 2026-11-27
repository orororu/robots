//// The root update. A feature's messages go to its own update (`menu`,
//// `hangar`, `map`, `garage`, `battle`) with just its state
//// and what it reads; the outcome is applied here, along with everything
//// impure: the clock, random seeds, saving, and messages to the player.

import gleam/int
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import robots/meta/profile.{type Profile}
import robots/run/save
import robots/run/state.{type Run}
import robots_client/battle/model.{Combat, Continue, Play, default_order} as battle_model
import robots_client/battle/update.{Env} as battle_update
import robots_client/common/browser
import robots_client/common/wording.{
  describe_error, describe_rejection, describe_reward,
}
import robots_client/garage/model.{Cancel, Garage, no_pick} as _
import robots_client/garage/update as garage_update
import robots_client/hangar/model.{hangar_for} as _
import robots_client/hangar/update as hangar_update
import robots_client/map/model.{Journal} as _
import robots_client/map/update as map_update
import robots_client/menu/model.{Menu} as _
import robots_client/menu/update as menu_update
import robots_client/model.{
  type Model, type Msg, BattleMsg, Frame, GarageMsg, HangarMsg, KeyDown, MapMsg,
  MenuMsg, Model, flash_ms, new_model,
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  #(step(model, msg), effect.none())
}

fn step(model: Model, msg: Msg) -> Model {
  case msg {
    Frame(now) -> {
      let model = Model(..model, now:)
      let #(combat, outcome) =
        battle_update.advance(model.combat, model.run, now)
      battle_outcome(Model(..model, combat:), outcome)
    }
    KeyDown(key) ->
      case key_message(model, key) {
        Some(msg) -> step(model, msg)
        None -> model
      }
    HangarMsg(msg) ->
      case model.hangar {
        Some(h) ->
          case
            hangar_update.update(h, model.profile, msg, browser.random_seed())
          {
            hangar_update.Changed(hangar:, profile:, message:) -> {
              save_profile(model.profile, profile)
              let model = Model(..model, hangar: Some(hangar), profile:)
              case message {
                "" -> model
                _ -> flash(model, message)
              }
            }
            hangar_update.Refused(reason) -> flash(model, reason)
            hangar_update.Started(profile:, run:) -> {
              save_profile(model.profile, profile)
              keep(run)
              new_model(run, profile, None, model.now)
            }
            hangar_update.Menu -> Model(..model, menu: Some(Menu(saved: None)))
          }
        None -> model
      }
    GarageMsg(msg) -> {
      let #(garage, outcome) =
        garage_update.update(model.garage, model.run, msg)
      let model = Model(..model, garage:)
      case outcome {
        garage_update.Nothing -> model
        garage_update.Failed(e) -> flash(model, describe_error(e))
        garage_update.Changed(run:, message:, loud:, upgraded:) -> {
          let model = case upgraded {
            Some(_) ->
              Model(..model, journal: Journal(..model.journal, upgraded:))
            None -> model
          }
          model |> change_run(run) |> tell(message, loud)
        }
      }
    }
    BattleMsg(msg) -> {
      // A fresh timestamp: the last frame may be up to 50ms old.
      let model = Model(..model, now: browser.now())
      let env =
        Env(
          now: model.now,
          seed: browser.random_seed(),
          brain_seed: browser.random_seed(),
        )
      let #(combat, outcome) =
        battle_update.update(model.combat, model.run, msg, env)
      battle_outcome(Model(..model, combat:), outcome)
    }
    MenuMsg(msg) ->
      case model.menu {
        Some(menu) ->
          case menu_update.update(menu, model.profile, msg) {
            menu_update.Nothing -> model
            menu_update.Continued(run) ->
              new_model(run, model.profile, None, model.now)
              |> tell("Run continued.", False)
            menu_update.ToHangar(p) ->
              open_hangar(Model(..model, menu: None), p)
          }
        None -> model
      }
    MapMsg(msg) -> {
      let #(journal, outcome) =
        map_update.update(model.journal, model.run, model.profile, msg)
      let model = Model(..model, journal:)
      case outcome {
        map_update.Went(run) ->
          Model(
            ..change_run(model, run),
            garage: Garage(..model.garage, pick: no_pick),
          )
        map_update.Failed(e) -> flash(model, describe_error(e))
        map_update.Finished(p) -> open_hangar(model, p)
      }
    }
  }
}

/// The keys: Enter leaves a battle report, 1-9 play a card, Escape clears
/// the garage's selection.
fn key_message(model: Model, key: String) -> Option(Msg) {
  case model.combat.battle, key {
    _, "Enter" if model.combat.report != None -> Some(BattleMsg(Continue))
    Some(_), _ ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> Some(BattleMsg(Play(n - 1)))
        _ -> None
      }
    None, "Escape" -> Some(GarageMsg(Cancel))
    None, _ -> None
  }
}

fn battle_outcome(model: Model, outcome: battle_update.Outcome) -> Model {
  case outcome {
    battle_update.Nothing -> model
    battle_update.Played -> Model(..model, flash: "")
    battle_update.Rejected(rejection) ->
      flash(model, describe_rejection(model.scale, rejection))
    battle_update.Failed(e) -> flash(model, describe_error(e))
    battle_update.Over(run:, report:) -> {
      let news = describe_reward(model.run, run, report.reward)
      keep(run)
      Model(
        ..model,
        run:,
        garage: Garage(..model.garage, pick: no_pick),
        journal: Journal(..model.journal, news:),
        flash: "",
        flash_until: 0,
      )
    }
  }
}

/// The run changed: save it, and reset the battle order (robots may have
/// come or gone).
fn change_run(model: Model, run: Run) -> Model {
  keep(run)
  Model(
    ..model,
    run:,
    combat: Combat(..model.combat, order: default_order(run)),
  )
}

/// Tell the player something: as news, and in the banner if `loud`.
fn tell(model: Model, message: String, loud: Bool) -> Model {
  case message, loud {
    "", _ -> model
    _, False -> Model(..model, journal: Journal(..model.journal, news: message))
    _, True ->
      flash(
        Model(..model, journal: Journal(..model.journal, news: message)),
        message,
      )
  }
}

fn flash(model: Model, text: String) -> Model {
  Model(..model, flash: text, flash_until: model.now + flash_ms)
}

/// Save the profile and go to the hangar; the run is over and paid out.
fn open_hangar(model: Model, p: Profile) -> Model {
  browser.save_profile(profile.encode(p))
  // Nothing to continue.
  browser.save_run("")
  Model(
    ..model,
    profile: p,
    hangar: Some(hangar_for(p)),
    combat: battle_model.new_combat(model.run),
  )
}

fn save_profile(before: Profile, after: Profile) -> Nil {
  case before == after {
    True -> Nil
    False -> browser.save_profile(profile.encode(after))
  }
}

/// Save the run, so a reload continues it.
fn keep(run: Run) -> Nil {
  browser.save_run(save.encode(run))
}
