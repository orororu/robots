//// The run's garage and the shop's counter: clicks change what's selected,
//// actions change the run. Pure: the root saves the run and shows the
//// messages.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robots/construction/part
import robots/run/state.{type Run}
import robots/run/upgrade
import robots_client/garage/model.{
  type Garage, type Msg, type Pick, type Tab, Assemble, Buy, Cancel,
  ClickChassis, ClickForSale, ClickInstalled, ClickOwnChassis, ClickSpare, Draft,
  ForSale, Garage, GoTab, Install, Leave, NewRobotTab, OwnChassis, Picked,
  Rebuild, Remove, Repair, RepairPicked, RobotTab, SellPicked, ShopTab,
  SpareChassis, StockPart, StockRobot, Swap, UpgradePicked, current_tab, no_pick,
  repair_target, upgrade_target,
}

/// What a message did to the run.
pub type Outcome {
  /// The run is unchanged.
  Nothing
  Failed(state.Error)
  /// The run after it, and what to tell the player ("" for nothing); `loud`
  /// also flashes it. `upgraded`: a workshop upgrade, for the map to show
  /// (the part's name and the card before and after).
  Changed(
    run: Run,
    message: String,
    loud: Bool,
    upgraded: Option(#(String, upgrade.Change)),
  )
}

pub fn update(g: Garage, run: Run, msg: Msg) -> #(Garage, Outcome) {
  let tab = current_tab(run, g.tab)
  case msg {
    GoTab(tab) -> #(Garage(tab:, pick: no_pick), Nothing)
    ClickInstalled(..)
    | ClickSpare(_)
    | ClickChassis(_)
    | ClickForSale(..)
    | ClickOwnChassis(_)
    | Cancel -> #(Garage(..g, pick: select(g.pick, tab, msg)), Nothing)
    Leave -> #(Garage(..g, tab: ShopTab), done(state.leave(run)))
    _ ->
      case act(run, g.pick, tab, msg) {
        #(Changed(..) as outcome, change) -> #(
          change(Garage(..g, pick: no_pick)),
          outcome,
        )
        #(outcome, _) -> #(g, outcome)
      }
  }
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

/// Garage and shop actions on the run, for what's selected: the outcome,
/// and how the garage changes on success (besides clearing the selection).
fn act(
  run: Run,
  pick: Pick,
  tab: Tab,
  msg: Msg,
) -> #(Outcome, fn(Garage) -> Garage) {
  let same = fn(g) { g }
  let plain = fn(result) { #(done(result), same) }
  case msg, pick {
    Repair(robot), _ -> plain(state.repair(run, robot))
    RepairPicked, _ ->
      case repair_target(pick) {
        Some(target) -> plain(state.repair_one(run, target))
        None -> #(Nothing, same)
      }
    SellPicked, Picked(None, Some(spare)) -> plain(state.sell(run, spare))
    Buy, ForSale(StockPart, i) -> plain(state.buy_part(run, i))
    Buy, ForSale(StockRobot, i) -> plain(state.buy_robot(run, i))
    Install(robot), Picked(_, Some(spare)) ->
      plain(state.install(run, robot, spare))
    Swap, Picked(Some(#(robot, p)), Some(spare)) ->
      plain(state.swap(run, robot, p, spare))
    Remove, Picked(Some(#(robot, p)), _) ->
      plain(state.uninstall(run, robot, p))
    Assemble, Draft(chassis, parts, _) -> {
      let name = "Robot " <> int.to_string(list.length(run.robots) + 1)
      let result = state.assemble(run, name, chassis, parts)
      // Open the new robot's room.
      let open = fn(g) { Garage(..g, tab: RobotTab(list.length(run.robots))) }
      #(done(result), open)
    }
    Rebuild, SpareChassis(c) ->
      case tab {
        RobotTab(r) ->
          case state.rebuild(run, r, c) {
            Ok(#(after, dropped)) -> #(
              Changed(
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
              ),
              same,
            )
            Error(e) -> #(Failed(e), same)
          }
        _ -> #(Nothing, same)
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
            Ok(#(name, after, change)) -> #(
              Changed(
                after,
                "Upgraded "
                  <> name
                  <> ": "
                  <> change.before.name
                  <> " → "
                  <> change.after.name
                  <> ".",
                False,
                Some(#(name, change)),
              ),
              same,
            )
            Error(e) -> #(Failed(e), same)
          }
        }
        None -> #(Nothing, same)
      }
    _, _ -> #(Nothing, same)
  }
}

fn done(result: Result(Run, state.Error)) -> Outcome {
  case result {
    Ok(run) -> Changed(run, "", False, None)
    Error(e) -> Failed(e)
  }
}
