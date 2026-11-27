//// The run's garage (and the shop's counter): what's selected, the open
//// tab, and their messages.

import gleam/list
import gleam/option.{type Option, None, Some}
import robots/run/state.{type Run}
import robots/run/upgrade

/// The garage's state during a run: what's selected, the open tab, and the
/// last workshop upgrade (shown on the map until the next step).
pub type Garage {
  Garage(pick: Pick, tab: Tab, upgraded: Option(#(String, upgrade.Change)))
}

pub fn new_garage() -> Garage {
  Garage(pick: no_pick, tab: ShopTab, upgraded: None)
}

/// What's selected in the garage; the selected parts' cards are shown.
pub type Pick {
  /// An installed part (robot, part) and/or a spare part. With one, it can
  /// be removed or installed; with both, swapped.
  Picked(installed: Option(#(Int, Int)), spare: Option(Int))
  /// A spare chassis and the spare parts chosen for a new robot; `last` is
  /// the spare clicked last, whose cards are shown.
  Draft(chassis: Int, parts: List(Int), last: Option(Int))
  /// The chassis of robot `robot` (to see its cards, or repair it).
  OwnChassis(robot: Int)
  /// Something a shop sells.
  ForSale(item: Stock, index: Int)
  /// A spare chassis, to rebuild the open tab's robot on.
  SpareChassis(index: Int)
}

/// The tabs over the garage: the shop's counter (at a repair shop), a
/// room per robot, and one to assemble a new robot.
pub type Tab {
  ShopTab
  RobotTab(robot: Int)
  NewRobotTab
}

/// The kinds of things a shop sells.
pub type Stock {
  StockPart
  StockRobot
}

pub const no_pick = Picked(None, None)

/// The garage's and the shop's messages.
pub type Msg {
  GoTab(Tab)
  ClickInstalled(robot: Int, part: Int)
  ClickSpare(part: Int)
  ClickChassis(chassis: Int)
  ClickOwnChassis(robot: Int)
  ClickForSale(item: Stock, index: Int)
  Cancel
  Install(robot: Int)
  Swap
  Remove
  Assemble
  /// Rebuild the open tab's robot on the selected spare chassis.
  Rebuild
  // Repair shop
  Repair(robot: Int)
  RepairPicked
  SellPicked
  Buy
  // Workshop
  UpgradePicked
  /// Leave the shop or workshop.
  Leave
}

/// What a repair would fix for this selection: one chassis or one part.
/// The one component selected, to upgrade at a workshop.
pub fn upgrade_target(pick: Pick) -> Option(state.Target) {
  case pick {
    Picked(Some(#(robot, p)), None) -> Some(state.Installed(robot, p))
    Picked(None, Some(spare)) -> Some(state.Spare(spare))
    _ -> None
  }
}

pub fn repair_target(pick: Pick) -> Option(state.Repair) {
  case pick {
    OwnChassis(robot) -> Some(state.RepairChassis(robot))
    Picked(Some(#(robot, p)), None) -> Some(state.RepairPart(robot, p))
    Picked(None, Some(spare)) -> Some(state.RepairSpare(spare))
    _ -> None
  }
}

pub fn at_shop(run: Run) -> Bool {
  case run.phase {
    state.Repairing(_) -> True
    _ -> False
  }
}

/// The open tab, made valid: the shop's counter only at a shop, a robot
/// that's still there (else the first, or New robot when there's none).
pub fn current_tab(run: Run, tab: Tab) -> Tab {
  let robots = list.length(run.robots)
  let first = case robots {
    0 -> NewRobotTab
    _ -> RobotTab(0)
  }
  case tab {
    ShopTab ->
      case at_shop(run) {
        True -> ShopTab
        False -> first
      }
    RobotTab(r) if r >= 0 && r < robots -> tab
    RobotTab(_) -> first
    NewRobotTab -> NewRobotTab
  }
}
