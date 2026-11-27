//// The client's state and messages (Model, Msg, picks, tabs, the hangar), and
//// pure helpers over them: what's selected, which tab is open, the
//// fabricator's spare components.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import robots/ai/brain
import robots/construction/builder
import robots/construction/part.{type Component}
import robots/construction/robot.{type Robot}
import robots/meta/blueprint.{
  type Blueprint, ChassisBlueprint, FabricatorBlueprint, PartBlueprint,
}
import robots/meta/profile.{type Profile}
import robots/rules/game.{type Game}
import robots/rules/scale.{type Scale}
import robots/run/state.{type Bot, type Run}
import robots/run/upgrade

pub const frame_ms = 50

pub const flash_ms = 2500

pub type Model {
  Model(
    /// What carries over between runs; saved in the browser.
    profile: Profile,
    /// Between runs: the hangar, where Data is spent and the starting
    /// robot designed. `run` is the last run (or a placeholder) meanwhile.
    hangar: Option(Hangar),
    /// The start menu: continue the saved run, or a new one.
    menu: Bool,
    /// The run saved in the browser, while the menu can continue it.
    saved: Option(Run),
    run: Run,
    /// The battle being fought, if any.
    battle: Option(Battle),
    /// How the last battle went, shown until the player continues.
    report: Option(Report),
    /// Battle order for the next battle: indexes into `run.robots`.
    order: List(Int),
    /// What's selected in the garage.
    pick: Pick,
    /// The open tab of the garage (the shop's counter first, at a shop).
    tab: Tab,
    /// What the last battle paid, shown on the map.
    news: String,
    /// The last workshop upgrade (part name, change), shown on the map
    /// until the next step.
    upgraded: Option(#(String, upgrade.Change)),
    scale: Scale,
    now: Int,
    flash: String,
    flash_until: Int,
  )
}

pub type Battle {
  Battle(
    game: Game,
    brain: brain.Brain,
    order: List(Int),
    /// The player's robots as they entered, in order.
    team: List(Robot),
    enemy: String,
    started: Int,
  )
}

pub type Report {
  Report(
    won: Bool,
    enemy: String,
    enemy_hp: Float,
    enemy_max_hp: Float,
    /// Each robot that fought: name, HP before, HP after, max HP.
    robots: List(#(String, Float, Float, Float)),
    seconds: Int,
    reward: state.Reward,
    /// The run's level before and after (a boss moves it on).
    level_before: Int,
    level_after: Int,
  )
}

/// The hangar: the design being edited (the fabricator's first robot) and
/// what's selected.
pub type Hangar {
  /// `designs`: the robots the fabricator builds, as edited (saved on
  /// starting a run).
  Hangar(designs: List(profile.Design), pick: HangarPick, screen: HangarScreen)
}

/// The hangar's screens: an overview, the research lab, the garage.
pub type HangarScreen {
  Overview
  Lab
  /// A design's room, like a run's robot tab.
  Room(Int)
  /// Make a new design from a spare chassis and components.
  NewRoom
}

pub type HangarPick {
  NoHangarPick
  /// A found blueprint, to research or sell.
  PickFound(Blueprint)
  /// In the garage, as in a run's: a part of the design and/or one of the
  /// fabricator's spare components (by index in `spare_parts`).
  PickGarage(installed: Option(Int), spare: Option(Int))
  /// One of the fabricator's spare chassis (in `spare_chassis`).
  PickSpareChassis(Int)
  /// The design's own chassis, to see its cards.
  PickDesignChassis
  /// In the new robot room: a spare chassis and the spare components
  /// chosen (indexes into `spare_chassis` and `spare_parts`).
  PickDraft(chassis: Int, parts: List(Int))
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

/// A model for `run`, in the hangar if `hangar` is given.
pub fn new_model(
  run: Run,
  profile: Profile,
  hangar: Option(Hangar),
  now: Int,
) -> Model {
  Model(
    profile:,
    hangar:,
    menu: False,
    saved: None,
    run:,
    battle: None,
    report: None,
    order: default_order(run),
    pick: no_pick,
    tab: ShopTab,
    news: "A new run. Pick where to go.",
    upgraded: None,
    scale: scale.default(),
    now:,
    flash: "",
    flash_until: 0,
  )
}

pub fn default_order(run: Run) -> List(Int) {
  int.range(0, list.length(run.robots), [], list.prepend) |> list.reverse
}

pub fn hangar_for(p: Profile) -> Hangar {
  Hangar(
    designs: list.take(p.designs, p.fabricator),
    pick: NoHangarPick,
    screen: Overview,
  )
}

/// The open room's design index (the first design outside a room).
pub fn room_index(h: Hangar) -> Int {
  case h.screen {
    Room(i) -> i
    _ -> 0
  }
}

pub fn room(h: Hangar) -> profile.Design {
  at(h.designs, room_index(h))
  |> option.unwrap(profile.Design("Robot", "Frame", []))
}

/// Change the open room's design; clears the selection.
pub fn set_room(h: Hangar, d: profile.Design) -> Hangar {
  let i = room_index(h)
  Hangar(
    ..h,
    designs: list.index_map(h.designs, fn(x, j) {
      case i == j {
        True -> d
        False -> x
      }
    }),
    pick: NoHangarPick,
  )
}

pub type Msg {
  Frame(now: Int)
  KeyDown(key: String)
  // Hangar
  HangarSelect(pick: HangarPick)
  Research
  SellBlueprint
  // The start screen
  ContinueRun
  NewGame
  ToMenu
  HangarGo(screen: HangarScreen)
  HangarInstalled(index: Int)
  HangarSpare(index: Int)
  HangarSpareChassis(index: Int)
  HangarOwnChassis
  AddPart
  RemovePart
  SwapPart
  UseChassis
  AssembleDesign
  StartRun
  /// After a run: pay it out and go to the hangar.
  ToHangar
  // Map
  Go(node: Int)
  // Before a battle
  First(robot: Int)
  Fight
  // Battle
  Play(slot: Int)
  Continue
  // Repair shop
  Repair(robot: Int)
  RepairPicked
  SellPicked
  Leave
  GoTab(Tab)
  /// Rebuild the open tab's robot on the selected spare chassis.
  Rebuild
  // Workshop
  UpgradePicked
  // Garage
  ClickInstalled(robot: Int, part: Int)
  ClickSpare(part: Int)
  ClickChassis(chassis: Int)
  ClickOwnChassis(robot: Int)
  ClickForSale(item: Stock, index: Int)
  Buy
  Install(robot: Int)
  Swap
  Remove
  Assemble
  Cancel
}

pub fn toggle(selected: Option(Int), i: Int) -> Option(Int) {
  case selected == Some(i) {
    True -> None
    False -> Some(i)
  }
}

pub fn tidy(pick: HangarPick) -> HangarPick {
  case pick {
    PickGarage(None, None) -> NoHangarPick
    _ -> pick
  }
}

pub fn at(items: List(a), i: Int) -> Option(a) {
  list.drop(items, i) |> list.first |> option.from_result
}

/// The fabricator's components the design doesn't use: one entry per
/// copy, in research order (each installed part takes one copy away).
pub fn spare_parts(
  p: Profile,
  designs: List(profile.Design),
) -> List(Component) {
  let made =
    list.filter_map(p.researched, fn(b) {
      case b {
        PartBlueprint(c) -> Ok(c)
        ChassisBlueprint(_) | FabricatorBlueprint -> Error(Nil)
      }
    })
  list.fold(list.flat_map(designs, fn(d) { d.parts }), made, remove_first)
}

/// The fabricator's chassis the design isn't built on.
pub fn spare_chassis(
  p: Profile,
  designs: List(profile.Design),
) -> List(String) {
  let made =
    list.filter_map(p.researched, fn(b) {
      case b {
        ChassisBlueprint(name) -> Ok(name)
        PartBlueprint(_) | FabricatorBlueprint -> Error(Nil)
      }
    })
  list.fold(list.map(designs, fn(d) { d.chassis }), made, remove_first)
}

pub fn remove_first(items: List(a), item: a) -> List(a) {
  case items {
    [] -> []
    [x, ..rest] if x == item -> rest
    [x, ..rest] -> [x, ..remove_first(rest, item)]
  }
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

/// The design as a robot, to show its weight and mounts (if its chassis
/// and parts exist; research and legality aside).
pub fn design_bot(d: profile.Design) -> Option(Bot) {
  case blueprint.chassis(d.chassis) {
    Ok(chassis) -> Some(state.Bot(name: d.name, chassis:, parts: d.parts))
    Error(Nil) -> None
  }
}

/// What a blueprint makes, as a component (a chassis as its body).
pub fn blueprint_component(b: Blueprint) -> Option(Component) {
  case b {
    PartBlueprint(p) -> Some(p)
    ChassisBlueprint(name) ->
      blueprint.chassis(name) |> result.map(builder.body) |> option.from_result
    FabricatorBlueprint -> None
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
