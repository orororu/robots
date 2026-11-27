//// The hangar between runs: the designs being edited, what's selected,
//// its messages, and the fabricator's spare components.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import robots/construction/builder
import robots/construction/part.{type Component}
import robots/meta/blueprint.{
  type Blueprint, ChassisBlueprint, FabricatorBlueprint, PartBlueprint,
}
import robots/meta/profile.{type Profile}
import robots/run/state.{type Bot}

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

/// The hangar's messages.
pub type Msg {
  HangarSelect(pick: HangarPick)
  HangarGo(screen: HangarScreen)
  Research
  SellBlueprint
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
  ToMenu
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
