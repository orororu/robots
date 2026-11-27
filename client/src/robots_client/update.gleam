//// The root update. A feature's messages go to its own update
//// (`hangar_update`, `garage_update`, `battle_update`) with just its state
//// and what it reads; the outcome is applied here, along with everything
//// impure: the clock, random seeds, saving, and messages to the player.

import gleam/int
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import robots/meta/profile.{type Profile}
import robots/run/save
import robots/run/state.{type Run}
import robots_client/battle_model.{Combat, Continue, Play, default_order}
import robots_client/battle_update.{Env}
import robots_client/browser
import robots_client/garage_model.{Cancel, Garage, no_pick}
import robots_client/garage_update
import robots_client/hangar_model.{hangar_for}
import robots_client/hangar_update
import robots_client/model.{
  type Model, type Msg, BattleMsg, ContinueRun, Frame, GarageMsg, Go, HangarMsg,
  KeyDown, Model, NewGame, ToHangar, flash_ms, new_model,
}
import robots_client/wording.{
  describe_error, describe_rejection, describe_reward,
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
              Model(..model, hangar: Some(hangar), profile:)
              |> tell(message, True)
            }
            hangar_update.Refused(reason) -> flash(model, reason)
            hangar_update.Started(profile:, run:) -> {
              save_profile(model.profile, profile)
              keep(run)
              new_model(run, profile, None, model.now)
            }
            hangar_update.Menu -> Model(..model, menu: True)
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
        garage_update.Changed(run:, message:, loud:) ->
          model |> change_run(run) |> tell(message, loud)
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
    ContinueRun ->
      case model.saved {
        Some(run) ->
          Model(
            ..new_model(run, model.profile, None, model.now),
            news: "Run continued.",
          )
        None -> model
      }
    // A saved run is abandoned: paid out like a lost one.
    NewGame ->
      case model.saved {
        Some(run) ->
          open_hangar(
            Model(..model, menu: False, saved: None),
            profile.finish(model.profile, run),
          )
        None ->
          Model(..model, menu: False, hangar: Some(hangar_for(model.profile)))
      }
    ToHangar -> open_hangar(model, profile.finish(model.profile, model.run))
    Go(node) ->
      case state.go(model.run, node) {
        Ok(run) ->
          Model(
            ..change_run(model, run),
            garage: Garage(..model.garage, pick: no_pick, upgraded: None),
          )
        Error(e) -> flash(model, describe_error(e))
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
        news:,
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
    _, False -> Model(..model, news: message)
    _, True -> flash(Model(..model, news: message), message)
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
