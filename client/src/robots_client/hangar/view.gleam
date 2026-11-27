//// The hangar between runs: the overview, the research lab, a tab per
//// robot design and a New robot tab.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/builder
import robots/construction/part
import robots/meta/blueprint.{type Blueprint, ChassisBlueprint, PartBlueprint}
import robots/meta/profile.{type Profile}
import robots/rules/scale.{type Scale}

import robots/run/price
import robots_client/common/kinds.{chassis_table, robot_table, spare_table}
import robots_client/common/preview.{preview_section}
import robots_client/common/ui.{button, button_class, picked, tabs, text}
import robots_client/common/wording.{
  describe_profile_error, robot_title, weight_line,
}
import robots_client/hangar/model.{
  type Hangar, type Msg, AddPart, AssembleDesign, HangarGo, HangarInstalled,
  HangarOwnChassis, HangarSelect, HangarSpare, HangarSpareChassis, Lab, NewRoom,
  NoHangarPick, Overview, PickDesignChassis, PickDraft, PickFound, PickGarage,
  PickSpareChassis, RemovePart, Research, Room, SellBlueprint, StartRun,
  SwapPart, ToMenu, UseChassis, at, blueprint_component, design_bot, room,
  spare_chassis, spare_parts,
}

/// What the hangar's views need: the profile, the hangar being edited, and
/// the display scale.
pub type HangarView {
  HangarView(profile: Profile, hangar: Hangar, scale: Scale)
}

pub fn view_hangar(v: HangarView) -> Element(Msg) {
  let h = v.hangar
  html.div([], [
    hangar_tabs(v),
    case h.screen {
      Overview -> view_hangar_overview(v)
      Lab -> view_lab(v)
      Room(_) -> design_room(v)
      NewRoom -> new_design_room(v)
    },
  ])
}

/// Whether the design can be fabricated, or why not.
pub fn design_status(p: Profile, d: profile.Design) -> Element(Msg) {
  case profile.fabricate(p, d) {
    Ok(_) -> text("ally", "✓ ready to fabricate")
    Error(e) -> text("foe", "✗ " <> describe_profile_error(e))
  }
}

pub fn design_lines(d: profile.Design) -> List(Element(Msg)) {
  case design_bot(d) {
    Some(b) -> [
      text("", "    " <> weight_line(b)),
    ]
    None -> []
  }
}

pub fn hangar_tabs(v: HangarView) -> Element(Msg) {
  let h = v.hangar
  let found = list.length(v.profile.found)
  tabs([
    #("Hangar", h.screen == Overview, HangarGo(Overview)),
    #(
      "Research lab"
        <> case found {
        0 -> ""
        n -> " (" <> int.to_string(n) <> ")"
      },
      h.screen == Lab,
      HangarGo(Lab),
    ),
    ..list.append(
      list.index_map(h.designs, fn(d, i) {
        #(d.name, h.screen == Room(i), HangarGo(Room(i)))
      }),
      [#("+ New robot", h.screen == NewRoom, HangarGo(NewRoom))],
    )
  ])
}

pub fn view_hangar_overview(v: HangarView) -> Element(Msg) {
  let h = v.hangar
  let p = v.profile
  html.div([], [
    text(
      "",
      "HANGAR · the truck carries "
        <> int.to_string(p.truck)
        <> " robots · the fabricator builds "
        <> int.to_string(p.fabricator)
        <> case p.fabricator {
        1 -> " robot"
        _ -> " robots"
      }
        <> " for each run from its components",
    ),
    button_class(">>> Start a run", "banner", StartRun),
    text("", "ROBOTS · change each in its tab"),
    html.div(
      [attribute.class("table")],
      list.flat_map(h.designs, fn(d) {
        [
          text(
            "ally",
            "  "
              <> d.name
              <> " ("
              <> d.chassis
              <> "): "
              <> string.join(list.map(d.parts, part.display_name), ", "),
          ),
          ..list.append(design_lines(d), [design_status(v.profile, d)])
        ]
      }),
    ),
    button("[Menu]", ToMenu),
  ])
}

pub fn view_lab(v: HangarView) -> Element(Msg) {
  let h = v.hangar
  let p = v.profile
  let found =
    list.map(p.found, fn(b) {
      button_class(
        "  "
          <> blueprint.describe(b)
          <> " · research "
          <> int.to_string(blueprint.research_cost(b))
          <> " Data",
        picked(h.pick == PickFound(b)),
        HangarSelect(PickFound(b)),
      )
    })
  let #(actions, preview) = case h.pick {
    PickFound(b) -> #(
      [
        button(
          "[Research · "
            <> int.to_string(blueprint.research_cost(b))
            <> " Data]",
          Research,
        ),
        sell_button(b),
      ],
      case blueprint_component(b) {
        Some(c) -> preview_section(v.scale, "", c)
        None ->
          text(
            "",
            "FABRICATOR UPGRADE · the fabricator builds "
              <> int.to_string(v.profile.fabricator + 1)
              <> " robots for each run instead of "
              <> int.to_string(v.profile.fabricator)
              <> ". Each robot needs its own components: design it in the + New robot tab.",
          )
      },
    )
    _ -> #([], text("dim", "Select a blueprint to see its cards."))
  }
  html.div([], [
    html.div([attribute.class("garage")], [
      html.div([], [
        text(
          "",
          "RESEARCH LAB · blueprints found in runs: research one to get its component in the fabricator",
        ),
        html.div([attribute.class("table")], case found {
          [] -> [
            text(
              "dim",
              "  none yet: strong enemies sometimes drop one, bosses always",
            ),
          ]
          _ -> found
        }),
        html.div([attribute.class("actions")], with_cancel(actions)),
      ]),
      html.div([attribute.class("preview")], [preview]),
    ]),
  ])
}

/// The fabricator's spare components, one per copy, in a table grouped by
/// kind; `chosen` are selected. Installing one takes it off the list.
pub fn fabricator_spare_rows(
  v: HangarView,
  chosen: List(Int),
) -> List(Element(Msg)) {
  let h = v.hangar
  case spare_parts(v.profile, h.designs) {
    [] -> [text("dim", "  none: research blueprints in the research lab")]
    parts -> [spare_table(v.scale, parts, chosen, HangarSpare)]
  }
}

/// The fabricator's spare chassis in a table (none: no rows); `chosen` is
/// selected.
pub fn fabricator_chassis_rows(
  v: HangarView,
  chosen: Option(Int),
) -> List(Element(Msg)) {
  let h = v.hangar
  let spares =
    spare_chassis(v.profile, h.designs)
    |> list.index_map(fn(name, i) {
      blueprint.chassis(name) |> result.map(fn(c) { #(i, c) })
    })
    |> result.values
  case spares {
    [] -> []
    _ -> [
      chassis_table(v.scale, spares, "Value", price.of_chassis, fn(i) {
        #(chosen == Some(i), HangarSpareChassis(i))
      }),
    ]
  }
}

pub fn spare_chassis_at(v: HangarView, i: Int) -> Option(builder.Chassis) {
  let h = v.hangar
  option.then(at(spare_chassis(v.profile, h.designs), i), fn(name) {
    option.from_result(blueprint.chassis(name))
  })
}

/// A design's room, like a robot's tab in a run: the robot, the
/// fabricator's spare components and chassis. Install, remove, swap,
/// rebuild on another chassis, or sell a spare.
pub fn design_room(v: HangarView) -> Element(Msg) {
  let h = v.hangar
  let s = v.scale
  let d = room(h)
  let spares = spare_parts(v.profile, h.designs)
  let #(installed, spare) = case h.pick {
    PickGarage(installed, spare) -> #(installed, spare)
    _ -> #(None, None)
  }
  let robot = case design_bot(d) {
    Some(bot) ->
      html.div([attribute.class("robot")], [
        text("ally", robot_title(s, bot)),
        ..list.flatten([
          [
            robot_table(
              s,
              bot,
              #(h.pick == PickDesignChassis, HangarOwnChassis),
              fn(i) { #(installed == Some(i), HangarInstalled(i)) },
            ),
          ],
          [design_status(v.profile, d)],
        ])
      ])
    None -> text("foe", "  " <> d.name <> ": unknown chassis")
  }
  let chosen_chassis = case h.pick {
    PickSpareChassis(i) -> Some(i)
    _ -> None
  }
  let chassis_rows = fabricator_chassis_rows(v, chosen_chassis)
  let actions = case h.pick {
    PickGarage(Some(_), Some(_)) -> [button("[Swap them]", SwapPart)]
    PickGarage(Some(_), None) -> [button("[Remove part]", RemovePart)]
    PickGarage(None, Some(j)) ->
      list.flatten([
        [button("[Install on " <> d.name <> "]", AddPart)],
        case at(spares, j) {
          Some(c) -> [sell_button(PartBlueprint(c))]
          None -> []
        },
      ])
    PickSpareChassis(i) ->
      list.flatten([
        [button("[Rebuild " <> d.name <> " on it]", UseChassis)],
        case at(spare_chassis(v.profile, h.designs), i) {
          Some(name) -> [sell_button(ChassisBlueprint(name))]
          None -> []
        },
      ])
    _ -> []
  }
  // What a rebuild would do.
  let check = case h.pick {
    PickSpareChassis(i) ->
      case spare_chassis_at(v, i) {
        Some(c) -> {
          let #(kept, dropped) = builder.fit(c, d.parts)
          case builder.build(d.name, c, kept) {
            Ok(_) -> [
              text("ally", case dropped {
                [] -> "✓ every part fits"
                _ ->
                  "✓ it works · back to the spares: "
                  <> string.join(list.map(dropped, part.display_name), ", ")
              }),
            ]
            Error(errors) -> [
              text(
                "foe",
                "✗ "
                  <> string.join(list.map(errors, builder.describe_error), "; "),
              ),
            ]
          }
        }
        None -> []
      }
    _ -> []
  }
  let previews = case h.pick {
    PickGarage(installed, spare) ->
      case
        option.then(installed, at(d.parts, _)),
        option.then(spare, at(spares, _))
      {
        Some(o), Some(n) -> [
          preview_section(v.scale, "OUT", o),
          preview_section(v.scale, "IN", n),
        ]
        Some(o), None -> [preview_section(v.scale, "", o)]
        None, Some(n) -> [preview_section(v.scale, "", n)]
        None, None -> []
      }
    PickSpareChassis(i) ->
      case spare_chassis_at(v, i) {
        Some(c) -> [preview_section(v.scale, "CHASSIS", builder.body(c))]
        None -> []
      }
    PickDesignChassis ->
      case blueprint.chassis(d.chassis) {
        Ok(c) -> [preview_section(v.scale, "", builder.body(c))]
        Error(Nil) -> []
      }
    _ -> []
  }
  let previews = case previews {
    [] -> [text("dim", "Select a part, component or chassis to see its cards.")]
    _ -> previews
  }
  let hint = case h.pick {
    PickGarage(Some(_), None) ->
      "remove it, or select a component to swap it for"
    PickGarage(None, Some(_)) ->
      "install it, or select an installed part to swap"
    PickGarage(Some(_), Some(_)) -> "swap them, or change either selection"
    PickSpareChassis(_) ->
      "rebuild the robot on it: the parts that fit move over"
    PickDesignChassis -> "the chassis' own cards"
    _ ->
      "select a part or component to see its cards; a spare chassis to rebuild on"
  }
  html.div([attribute.class("garage")], [
    html.div([], [
      text("", d.name <> " · " <> hint),
      html.div([attribute.class("table")], [robot]),
      text(
        "",
        "FABRICATOR · spare components it can make, one per researched blueprint",
      ),
      html.div(
        [attribute.class("table")],
        fabricator_spare_rows(v, option.values([spare])),
      ),
      case chassis_rows {
        [] -> text("", "")
        _ ->
          html.div([attribute.class("table")], [
            text("", "SPARE CHASSIS · rebuild " <> d.name <> " on one"),
            ..chassis_rows
          ])
      },
      html.div([attribute.class("actions")], with_cancel(actions)),
      ..check
    ]),
    html.div([attribute.class("preview")], previews),
  ])
}

/// A new design from a spare chassis and spare components, while the
/// fabricator has room for another robot.
pub fn new_design_room(v: HangarView) -> Element(Msg) {
  let h = v.hangar
  let p = v.profile
  let spares = spare_parts(p, h.designs)
  let #(chassis, drafted) = case h.pick {
    PickDraft(c, parts) -> #(Some(c), parts)
    _ -> #(None, [])
  }
  let room_left = list.length(h.designs) < p.fabricator
  let chassis_rows = fabricator_chassis_rows(v, chassis)
  let #(actions, check) = case h.pick, room_left {
    PickDraft(c, parts), True -> {
      let attempt =
        option.map(spare_chassis_at(v, c), fn(frame) {
          builder.build(
            "New",
            frame,
            list.filter_map(parts, fn(j) {
              at(spares, j) |> option.to_result(Nil)
            }),
          )
        })
      #([button("[Assemble robot]", AssembleDesign)], case attempt {
        Some(Ok(_)) -> [text("ally", "✓ it can be built")]
        Some(Error(errors)) -> [
          text(
            "foe",
            "✗ " <> string.join(list.map(errors, builder.describe_error), "; "),
          ),
        ]
        None -> []
      })
    }
    _, _ -> #([], [])
  }
  let previews = case h.pick {
    PickDraft(c, parts) ->
      list.flatten([
        case spare_chassis_at(v, c) {
          Some(frame) -> [
            preview_section(v.scale, "CHASSIS", builder.body(frame)),
          ]
          None -> []
        },
        case list.last(parts) {
          Ok(j) ->
            case at(spares, j) {
              Some(part) -> [preview_section(v.scale, "PART", part)]
              None -> []
            }
          Error(Nil) -> []
        },
      ])
    _ -> [text("dim", "Select a spare chassis to build on.")]
  }
  html.div([attribute.class("garage")], [
    html.div([], [
      text(
        "",
        "NEW ROBOT · "
          <> case room_left, chassis_rows, chassis {
          False, _, _ ->
            "the fabricator builds "
            <> int.to_string(p.fabricator)
            <> case p.fabricator {
              1 -> " robot"
              _ -> " robots"
            }
            <> " a run: an upgrade will let it build more"
          True, [], _ -> "no spare chassis: research a chassis blueprint"
          True, _, None -> "select a spare chassis to build on"
          True, _, Some(_) -> "select components for it, then assemble"
        },
      ),
      html.div([attribute.class("table")], [
        text("", "SPARE CHASSIS"),
        ..case chassis_rows {
          [] -> [text("dim", "  none")]
          _ -> chassis_rows
        }
      ]),
      text("", "FABRICATOR · spare components"),
      html.div([attribute.class("table")], fabricator_spare_rows(v, drafted)),
      html.div([attribute.class("actions")], with_cancel(actions)),
      ..check
    ]),
    html.div([attribute.class("preview")], previews),
  ])
}

pub fn sell_button(b: Blueprint) -> Element(Msg) {
  button(
    "[Sell · +" <> int.to_string(profile.sell_price(b)) <> " Data]",
    SellBlueprint,
  )
}

/// The actions, then [Cancel] to clear the hangar's selection.
pub fn with_cancel(actions: List(Element(Msg))) -> List(Element(Msg)) {
  case actions {
    [] -> []
    _ -> list.append(actions, [button("[Cancel]", HangarSelect(NoHangarPick))])
  }
}
