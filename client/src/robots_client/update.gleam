//// Messages during a run (map, battles, shops, the garage) and the menu; the
//// hangar's go to `hangar_update`.

import gleam/int
import gleam/list
import gleam/option.{None, Some}

import gleam/string
import lustre/effect.{type Effect}
import robots/ai/brain

import robots/construction/part

import robots/content/enemies

import robots/meta/profile
import robots/rules/game.{P1, P2}

import robots/run/state
import robots_client/browser

import robots_client/model.{
  type Model, type Msg, AddPart, Assemble, AssembleDesign, Battle, Buy, Cancel,
  ClickChassis, ClickForSale, ClickInstalled, ClickOwnChassis, ClickSpare,
  Continue, ContinueRun, Draft, Fight, First, ForSale, Frame, Go, GoTab,
  HangarGo, HangarInstalled, HangarOwnChassis, HangarSelect, HangarSpare,
  HangarSpareChassis, Install, KeyDown, Leave, Model, NewGame, NewRobotTab,
  OwnChassis, Picked, Play, Rebuild, Remove, RemovePart, Repair, RepairPicked,
  Report, Research, RobotTab, SellBlueprint, SellPicked, ShopTab, SpareChassis,
  StartRun, StockPart, StockRobot, Swap, SwapPart, ToHangar, ToMenu,
  UpgradePicked, UseChassis, current_tab, default_order, hangar_for, new_model,
  no_pick, repair_target, upgrade_target,
}
import robots_client/wording.{
  describe_error, describe_rejection, describe_reward,
}

/// Save the profile and go to the hangar.
import robots_client/actions.{attempt, flash, keep, open_hangar}
import robots_client/hangar_update

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
    Continue -> continue(model)
    Repair(robot) -> attempt(model, state.repair(model.run, robot), "")
    RepairPicked ->
      case repair_target(model.pick) {
        Some(target) -> attempt(model, state.repair_one(model.run, target), "")
        None -> model
      }
    SellPicked ->
      case model.pick {
        Picked(None, Some(spare)) ->
          attempt(model, state.sell(model.run, spare), "")
        _ -> model
      }
    Leave -> attempt(Model(..model, tab: ShopTab), state.leave(model.run), "")
    GoTab(tab) -> Model(..model, tab:, pick: no_pick)
    Rebuild ->
      case model.pick, current_tab(model) {
        SpareChassis(c), RobotTab(r) ->
          case state.rebuild(model.run, r, c) {
            Ok(#(run, dropped)) -> {
              let message =
                case dropped {
                  [] -> "Rebuilt: every part fits."
                  _ ->
                    "Rebuilt. To the spares: "
                    <> string.join(list.map(dropped, part.display_name), ", ")
                    <> "."
                }
                <> " The old chassis is a spare."
              flash(attempt(model, Ok(run), message), message)
            }
            Error(e) -> attempt(model, Error(e), "")
          }
        _, _ -> model
      }
    UpgradePicked ->
      case upgrade_target(model.pick) {
        Some(target) ->
          case
            state.target_part(model.run, target),
            state.upgrade(model.run, target)
          {
            Ok(p), Ok(#(run, change)) ->
              attempt(
                Model(..model, upgraded: Some(#(part.display_name(p), change))),
                Ok(run),
                "Upgraded "
                  <> part.display_name(p)
                  <> ": "
                  <> change.before.name
                  <> " → "
                  <> change.after.name
                  <> ".",
              )
            _, Error(error) -> attempt(model, Error(error), "")
            Error(error), _ -> attempt(model, Error(error), "")
          }
        None -> model
      }
    ClickInstalled(robot, p) -> {
      let spare = case model.pick {
        Picked(_, spare) -> spare
        Draft(..) | OwnChassis(_) | ForSale(..) | SpareChassis(_) -> None
      }
      let installed = case model.pick {
        Picked(Some(picked), _) if picked == #(robot, p) -> None
        _ -> Some(#(robot, p))
      }
      Model(..model, pick: Picked(installed, spare))
    }
    ClickSpare(spare) -> click_spare(model, spare)
    ClickChassis(chassis) ->
      Model(..model, pick: case current_tab(model), model.pick {
        NewRobotTab, Draft(c, _, _) if c == chassis -> no_pick
        NewRobotTab, _ -> Draft(chassis, [], None)
        _, SpareChassis(c) if c == chassis -> no_pick
        _, _ -> SpareChassis(chassis)
      })
    ClickForSale(item, i) ->
      Model(..model, pick: case model.pick {
        ForSale(it, j) if it == item && j == i -> no_pick
        _ -> ForSale(item, i)
      })
    Buy ->
      case model.pick {
        ForSale(StockPart, i) ->
          attempt(model, state.buy_part(model.run, i), "")
        ForSale(StockRobot, i) ->
          attempt(model, state.buy_robot(model.run, i), "")
        _ -> model
      }
    ClickOwnChassis(robot) ->
      Model(..model, pick: case model.pick {
        OwnChassis(r) if r == robot -> no_pick
        _ -> OwnChassis(robot)
      })
    Install(robot) ->
      case model.pick {
        Picked(_, Some(spare)) ->
          attempt(model, state.install(model.run, robot, spare), "")
        _ -> model
      }
    Swap ->
      case model.pick {
        Picked(Some(#(robot, p)), Some(spare)) ->
          attempt(model, state.swap(model.run, robot, p, spare), "")
        _ -> model
      }
    Remove ->
      case model.pick {
        Picked(Some(#(robot, p)), _) ->
          attempt(model, state.uninstall(model.run, robot, p), "")
        _ -> model
      }
    Assemble ->
      case model.pick {
        Draft(chassis, parts, _) -> {
          let name =
            "Robot " <> int.to_string(list.length(model.run.robots) + 1)
          let after =
            attempt(model, state.assemble(model.run, name, chassis, parts), "")
          // Open the new robot's room.
          case list.length(after.run.robots) > list.length(model.run.robots) {
            True ->
              Model(..after, tab: RobotTab(list.length(after.run.robots) - 1))
            False -> after
          }
        }
        _ -> model
      }
    Cancel -> Model(..model, pick: no_pick)
  }
  #(model, effect.none())
}

pub fn key_down(model: Model, key: String) -> Model {
  case model.battle, key {
    _, "Enter" if model.report != None -> continue(model)
    Some(_), _ ->
      case int.parse(key) {
        Ok(n) if n >= 1 && n <= 9 -> play(model, n - 1)
        _ -> model
      }
    None, "Escape" -> Model(..model, pick: no_pick)
    None, _ -> model
  }
}

pub fn click_spare(model: Model, spare: Int) -> Model {
  case model.pick {
    Draft(chassis, parts, _) ->
      Model(
        ..model,
        pick: Draft(
          chassis,
          case list.contains(parts, spare) {
            True -> list.filter(parts, fn(i) { i != spare })
            False -> list.append(parts, [spare])
          },
          Some(spare),
        ),
      )
    Picked(installed, Some(picked)) if picked == spare ->
      Model(..model, pick: Picked(installed, None))
    Picked(installed, _) -> Model(..model, pick: Picked(installed, Some(spare)))
    OwnChassis(_) | ForSale(..) | SpareChassis(_) ->
      Model(..model, pick: Picked(None, Some(spare)))
  }
}

pub fn fight(model: Model) -> Model {
  case state.battle(model.run), state.team(model.run, model.order) {
    Ok(#(_, enemy)), Ok(team) -> {
      let now = browser.now()
      let game =
        game.teams(
          game.default_config(),
          p1: team,
          p2: [enemies.robot(enemy)],
          seed: browser.random_seed(),
          now:,
        )
      let brain =
        brain.new(P2, reaction: brain.human, seed: browser.random_seed())
      Model(
        ..model,
        battle: Some(Battle(
          game:,
          brain:,
          order: model.order,
          team:,
          enemy: enemy.name,
          started: now,
        )),
      )
    }
    Error(error), _ | _, Error(error) -> flash(model, describe_error(error))
  }
}

/// Let time pass and give the AI a chance to act.
pub fn advance(model: Model, now: Int) -> Model {
  case model.battle {
    Some(b) -> {
      let #(brain, game) = brain.act(b.brain, b.game, now)
      end_if_over(
        Model(..model, battle: Some(Battle(..b, game:, brain:)), now:),
      )
    }
    None -> Model(..model, now:)
  }
}

pub fn play(model: Model, slot: Int) -> Model {
  // Use a fresh timestamp: the last frame may be up to 50ms old.
  let model = advance(model, browser.now())
  case model.battle {
    Some(b) ->
      case game.update(b.game, game.PlayCard(P1, slot, model.now)) {
        Ok(game) ->
          end_if_over(
            Model(..model, battle: Some(Battle(..b, game:)), flash: ""),
          )
        Error(rejection) ->
          flash(model, describe_rejection(model.scale, rejection))
      }
    None -> model
  }
}

/// Once the battle is over, report it to the run (damage, losses, loot)
/// and show the battle report. The battle stops: no more ticking.
pub fn end_if_over(model: Model) -> Model {
  case model.battle {
    Some(b) if b.game.status != game.Running -> {
      let outcome = state.outcome(b.game, list.length(b.order))
      case state.finish(model.run, b.order, outcome) {
        Ok(#(run, reward)) -> {
          keep(run)
          let report =
            Report(
              won: outcome.won,
              enemy: b.enemy,
              enemy_hp: b.game.p2.robot.hp,
              enemy_max_hp: b.game.p2.robot.max_hp,
              robots: list.map(list.zip(b.team, outcome.hp_left), fn(pair) {
                let #(r, after) = pair
                #(r.name, r.hp, after, r.max_hp)
              }),
              seconds: { model.now - b.started } / 1000,
              reward:,
              level_before: model.run.level,
              level_after: run.level,
            )
          Model(
            ..model,
            run:,
            battle: None,
            report: Some(report),
            flash: "",
            flash_until: 0,
            pick: no_pick,
            order: default_order(run),
            news: describe_reward(model.run, run, reward),
          )
        }
        Error(error) -> flash(model, describe_error(error))
      }
    }
    _ -> model
  }
}

/// Leave the battle report.
pub fn continue(model: Model) -> Model {
  Model(..model, report: None)
}
