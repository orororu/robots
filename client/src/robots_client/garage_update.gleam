//// The run's garage messages, pure: clicks change what's selected
//// (`select`); actions change the run (`act`) and say what happened.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robots/construction/part
import robots/run/state.{type Run}
import robots/run/upgrade
import robots_client/model.{
  type Msg, type Pick, type Tab, Assemble, Buy, Cancel, ClickChassis,
  ClickForSale, ClickInstalled, ClickOwnChassis, ClickSpare, Draft, ForSale,
  Install, NewRobotTab, OwnChassis, Picked, Rebuild, Remove, Repair,
  RepairPicked, RobotTab, SellPicked, SpareChassis, StockPart, StockRobot, Swap,
  UpgradePicked, no_pick, repair_target, upgrade_target,
}

/// What an action did.
pub type Outcome {
  /// Nothing selected for it: nothing happens.
  Nothing
  Failed(state.Error)
  Done(
    run: Run,
    /// What to tell the player ("" for nothing).
    message: String,
    /// Also flash the message, not only show it as news.
    loud: Bool,
    /// A tab to open (the robot just assembled).
    open: Option(Tab),
    /// An upgrade to show: the part's name and the card before and after.
    upgraded: Option(#(String, upgrade.Change)),
  )
}

/// Clicks in the garage and the shop: the new selection. `tab` is the open
/// tab (see `model.current_tab`).
pub fn select(pick: Pick, tab: Tab, msg: Msg) -> Pick {
  case msg {
    ClickInstalled(robot, p) -> {
      let spare = case pick {
        Picked(_, spare) -> spare
        Draft(..) | OwnChassis(_) | ForSale(..) | SpareChassis(_) -> None
      }
      let installed = case pick {
        Picked(Some(picked), _) if picked == #(robot, p) -> None
        _ -> Some(#(robot, p))
      }
      Picked(installed, spare)
    }
    ClickSpare(spare) -> click_spare(pick, spare)
    ClickChassis(chassis) ->
      case tab, pick {
        NewRobotTab, Draft(c, _, _) if c == chassis -> no_pick
        NewRobotTab, _ -> Draft(chassis, [], None)
        _, SpareChassis(c) if c == chassis -> no_pick
        _, _ -> SpareChassis(chassis)
      }
    ClickForSale(item, i) ->
      case pick {
        ForSale(it, j) if it == item && j == i -> no_pick
        _ -> ForSale(item, i)
      }
    ClickOwnChassis(robot) ->
      case pick {
        OwnChassis(r) if r == robot -> no_pick
        _ -> OwnChassis(robot)
      }
    Cancel -> no_pick
    _ -> pick
  }
}

/// A spare: added to (or taken off) a new robot's parts, or selected.
fn click_spare(pick: Pick, spare: Int) -> Pick {
  case pick {
    Draft(chassis, parts, _) ->
      Draft(
        chassis,
        case list.contains(parts, spare) {
          True -> list.filter(parts, fn(i) { i != spare })
          False -> list.append(parts, [spare])
        },
        Some(spare),
      )
    Picked(installed, Some(picked)) if picked == spare -> Picked(installed, None)
    Picked(installed, _) -> Picked(installed, Some(spare))
    OwnChassis(_) | ForSale(..) | SpareChassis(_) -> Picked(None, Some(spare))
  }
}

/// Garage and shop actions on the run, for what's selected.
pub fn act(run: Run, pick: Pick, tab: Tab, msg: Msg) -> Outcome {
  case msg, pick {
    Repair(robot), _ -> quiet(state.repair(run, robot))
    RepairPicked, _ ->
      case repair_target(pick) {
        Some(target) -> quiet(state.repair_one(run, target))
        None -> Nothing
      }
    SellPicked, Picked(None, Some(spare)) -> quiet(state.sell(run, spare))
    Buy, ForSale(StockPart, i) -> quiet(state.buy_part(run, i))
    Buy, ForSale(StockRobot, i) -> quiet(state.buy_robot(run, i))
    Install(robot), Picked(_, Some(spare)) ->
      quiet(state.install(run, robot, spare))
    Swap, Picked(Some(#(robot, p)), Some(spare)) ->
      quiet(state.swap(run, robot, p, spare))
    Remove, Picked(Some(#(robot, p)), _) ->
      quiet(state.uninstall(run, robot, p))
    Assemble, Draft(chassis, parts, _) -> {
      let name = "Robot " <> int.to_string(list.length(run.robots) + 1)
      case state.assemble(run, name, chassis, parts) {
        // Open the new robot's room.
        Ok(after) ->
          Done(
            after,
            "",
            False,
            Some(RobotTab(list.length(after.robots) - 1)),
            None,
          )
        Error(e) -> Failed(e)
      }
    }
    Rebuild, SpareChassis(c) ->
      case tab {
        RobotTab(r) ->
          case state.rebuild(run, r, c) {
            Ok(#(after, dropped)) ->
              Done(
                after,
                case dropped {
                  [] -> "Rebuilt: every part fits."
                  _ ->
                    "Rebuilt. To the spares: "
                    <> string.join(list.map(dropped, part.display_name), ", ")
                    <> "."
                }
                  <> " The old chassis is a spare.",
                True,
                None,
                None,
              )
            Error(e) -> Failed(e)
          }
        _ -> Nothing
      }
    UpgradePicked, _ ->
      case upgrade_target(pick) {
        Some(target) -> {
          let upgraded = {
            use p <- result.try(state.target_part(run, target))
            use #(after, change) <- result.map(state.upgrade(run, target))
            #(part.display_name(p), after, change)
          }
          case upgraded {
            Ok(#(name, after, change)) ->
              Done(
                after,
                "Upgraded "
                  <> name
                  <> ": "
                  <> change.before.name
                  <> " → "
                  <> change.after.name
                  <> ".",
                False,
                None,
                Some(#(name, change)),
              )
            Error(e) -> Failed(e)
          }
        }
        None -> Nothing
      }
    _, _ -> Nothing
  }
}

fn quiet(result: Result(Run, state.Error)) -> Outcome {
  case result {
    Ok(run) -> Done(run, "", False, None, None)
    Error(e) -> Failed(e)
  }
}
