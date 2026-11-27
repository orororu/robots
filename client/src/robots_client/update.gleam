//// Routes messages to the pure steps (`hangar_update`, `garage_update`,
//// `battle_update`) and applies them to the model: the clock, random seeds,
//// saving and messages happen here.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/effect.{type Effect}
import robots/meta/profile
import robots/run/state
import robots_client/actions.{attempt, flash, keep, open_hangar}
import robots_client/battle_update
import robots_client/browser
import robots_client/garage_update.{Done, Failed, Nothing}
import robots_client/hangar_update
import robots_client/model.{
  type Model, type Msg, AddPart, Assemble, AssembleDesign, Buy, Cancel,
  ClickChassis, ClickForSale, ClickInstalled, ClickOwnChassis, ClickSpare,
  Continue, ContinueRun, Fight, First, Frame, Go, GoTab, HangarGo,
  HangarInstalled, HangarOwnChassis, HangarSelect, HangarSpare,
  HangarSpareChassis, Install, KeyDown, Leave, Model, NewGame, Play, Rebuild,
  Remove, RemovePart, Repair, RepairPicked, Research, SellBlueprint, SellPicked,
  ShopTab, StartRun, Swap, SwapPart, ToHangar, ToMenu, UpgradePicked, UseChassis,
  current_tab, default_order, hangar_for, new_model, no_pick,
}
import robots_client/wording.{
  describe_error, describe_rejection, describe_reward,
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let model = case msg {
    Frame(now) -> advance(model, now)
    KeyDown(key) -> key_down(model, key)
    HangarSelect(_)
    | Research
    | HangarInstalled(_)
    | HangarSpare(_)
    | HangarSpareChassis(_)
    | HangarOwnChassis
    | AddPart
    | RemovePart
    | SwapPart
    | UseChassis
    | AssembleDesign
    | SellBlueprint
    | StartRun
    | HangarGo(_) -> hangar_update.update(model, msg)
    ClickInstalled(..)
    | ClickSpare(_)
    | ClickChassis(_)
    | ClickForSale(..)
    | ClickOwnChassis(_)
    | Cancel ->
      Model(
        ..model,
        pick: garage_update.select(
          model.pick,
          current_tab(model.run, model.tab),
          msg,
        ),
      )
    Repair(_)
    | RepairPicked
    | SellPicked
    | Buy
    | Install(_)
    | Swap
    | Remove
    | Assemble
    | Rebuild
    | UpgradePicked -> garage_action(model, msg)
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
    ToMenu -> Model(..model, menu: True)
    ToHangar -> open_hangar(model, profile.finish(model.profile, model.run))
    Go(node) ->
      attempt(Model(..model, upgraded: None), state.go(model.run, node), "")
    First(robot) ->
      Model(..model, order: [
        robot,
        ..list.filter(model.order, fn(i) { i != robot })
      ])
    Fight -> fight(model)
    Play(slot) -> play(model, slot)
    Continue -> Model(..model, report: None)
    Leave -> attempt(Model(..model, tab: ShopTab), state.leave(model.run), "")
    GoTab(tab) -> Model(..model, tab:, pick: no_pick)
  }
  #(model, effect.none())
}

/// A garage or shop action: apply what it did to the run.
fn garage_action(model: Model, msg: Msg) -> Model {
  let tab = current_tab(model.run, model.tab)
  case garage_update.act(model.run, model.pick, tab, msg) {
    Nothing -> model
    Failed(e) -> flash(model, describe_error(e))
    Done(run:, message:, loud:, open:, upgraded:) -> {
      let model =
        Model(..model, upgraded: case upgraded {
          Some(_) -> upgraded
          None -> model.upgraded
        })
      let model = attempt(model, Ok(run), message)
      let model = case open {
        Some(tab) -> Model(..model, tab:)
        None -> model
      }
      case loud {
        True -> flash(model, message)
        False -> model
      }
    }
  }
}

fn key_down(model: Model, key: String) -> Model {
  case model.battle, key {
    _, "Enter" if model.report != None -> Model(..model, report: None)
    Some(_), _ ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> play(model, n - 1)
        _ -> model
      }
    None, "Escape" -> Model(..model, pick: no_pick)
    None, _ -> model
  }
}

fn fight(model: Model) -> Model {
  let now = browser.now()
  case
    battle_update.start(
      model.run,
      model.order,
      now,
      browser.random_seed(),
      browser.random_seed(),
    )
  {
    Ok(b) -> Model(..model, battle: Some(b))
    Error(error) -> flash(model, describe_error(error))
  }
}

/// Let time pass: the AI acts, and a battle that's over is reported.
fn advance(model: Model, now: Int) -> Model {
  case model.battle {
    Some(b) ->
      end_if_over(
        Model(..model, battle: Some(battle_update.tick(b, now)), now:),
      )
    None -> Model(..model, now:)
  }
}

fn play(model: Model, slot: Int) -> Model {
  // Use a fresh timestamp: the last frame may be up to 50ms old.
  let model = advance(model, browser.now())
  case model.battle {
    Some(b) ->
      case battle_update.play(b, slot, model.now) {
        Ok(b) -> end_if_over(Model(..model, battle: Some(b), flash: ""))
        Error(rejection) ->
          flash(model, describe_rejection(model.scale, rejection))
      }
    None -> model
  }
}

/// Once the battle is over, report it to the run and show the report. The
/// battle stops: no more ticking.
fn end_if_over(model: Model) -> Model {
  case model.battle {
    None -> model
    Some(b) ->
      case battle_update.finish(model.run, b, model.now) {
        Ok(None) -> model
        Ok(Some(#(run, report))) -> {
          keep(run)
          Model(
            ..model,
            run:,
            battle: None,
            report: Some(report),
            flash: "",
            flash_until: 0,
            pick: no_pick,
            order: default_order(run),
            news: describe_reward(model.run, run, report.reward),
          )
        }
        Error(error) -> flash(model, describe_error(error))
      }
  }
}
