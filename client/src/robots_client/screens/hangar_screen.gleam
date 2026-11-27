//// The hangar between runs: the overview, the research lab, a tab per
//// robot design and a New robot tab.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/builder
import robots/construction/part
import robots/meta/blueprint.{type Blueprint, ChassisBlueprint, PartBlueprint}
import robots/meta/profile
import robots/rules/scale

import robots_client/components/preview.{preview_section}
import robots_client/components/ui.{
  button, button_class, picked, tabs, text, with_cancel,
}
import robots_client/model.{
  type Hangar, type Model, type Msg, AddPart, AssembleDesign, HangarGo,
  HangarInstalled, HangarOwnChassis, HangarSelect, HangarSpare,
  HangarSpareChassis, Lab, NewRoom, Overview, PickDesignChassis, PickDraft,
  PickFound, PickGarage, PickSpareChassis, RemovePart, Research, Room,
  SellBlueprint, StartRun, SwapPart, ToMenu, UseChassis, at, blueprint_component,
  design_bot, room, spare_chassis, spare_parts,
}
import robots_client/wording.{
  bot_line, by_kind, describe_profile_error, kind_plural, mounts_line, num,
  own_chassis_line, part_line, weight_line,
}

pub fn view_hangar(model: Model) -> Element(Msg) {
  let assert Some(h) = model.hangar
  html.div([], [
    hangar_tabs(model, h),
    case h.screen {
      Overview -> view_hangar_overview(model, h)
      Lab -> view_lab(model, h)
      Room(_) -> design_room(model, h)
      NewRoom -> new_design_room(model, h)
    },
  ])
}

/// Whether the design can be fabricated, or why not.
pub fn design_status(model: Model, d: profile.Design) -> Element(Msg) {
  case profile.fabricate(model.profile, d) {
    Ok(_) -> text("ally", "✓ ready to fabricate")
    Error(e) -> text("foe", "✗ " <> describe_profile_error(e))
  }
}

pub fn design_lines(d: profile.Design) -> List(Element(Msg)) {
  case design_bot(d) {
    Some(b) -> [
      text("", "    " <> weight_line(b)),
      text("", "    " <> mounts_line(b)),
    ]
    None -> []
  }
}

pub fn hangar_tabs(model: Model, h: Hangar) -> Element(Msg) {
  let found = list.length(model.profile.found)
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

pub fn view_hangar_overview(model: Model, h: Hangar) -> Element(Msg) {
  let p = model.profile
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
          ..list.append(design_lines(d), [design_status(model, d)])
        ]
      }),
    ),
    button("[Menu]", ToMenu),
  ])
}

pub fn view_lab(model: Model, h: Hangar) -> Element(Msg) {
  let p = model.profile
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
        Some(c) -> preview_section(model, "", c)
        None ->
          text(
            "",
            "FABRICATOR UPGRADE · the fabricator builds "
              <> int.to_string(model.profile.fabricator + 1)
              <> " robots for each run instead of "
              <> int.to_string(model.profile.fabricator)
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

/// The garage between runs: the design as a robot, as in a run's garage,
/// and the fabricator's spare components below it, one per copy, grouped
/// by kind. Installing one takes it off the list.
/// The fabricator's spare components, grouped by kind; `chosen` selected.
pub fn fabricator_spare_rows(
  model: Model,
  h: Hangar,
  chosen: List(Int),
) -> List(Element(Msg)) {
  let rows =
    by_kind(spare_parts(model.profile, h.designs))
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "  " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let #(i, c) = pair
          button_class(
            "    " <> part_line(model.scale, c),
            picked(list.contains(chosen, i)),
            HangarSpare(i),
          )
        })
      ]
    })
  case rows {
    [] -> [text("dim", "  none: research blueprints in the research lab")]
    _ -> rows
  }
}

pub fn fabricator_chassis_rows(
  model: Model,
  h: Hangar,
  chosen: Option(Int),
) -> List(Element(Msg)) {
  list.index_map(spare_chassis(model.profile, h.designs), fn(name, i) {
    case blueprint.chassis(name) {
      Ok(c) ->
        button_class(
          "  "
            <> c.name
            <> " chassis · "
            <> int.to_string(scale.value(model.scale, c.hp))
            <> " HP · max weight "
            <> num(c.capacity)
            <> " · weapon mounts up to "
            <> string.join(list.map(c.weapon_mounts, num), ", "),
          picked(chosen == Some(i)),
          HangarSpareChassis(i),
        )
      Error(Nil) -> text("dim", "  " <> name)
    }
  })
}

pub fn spare_chassis_at(
  model: Model,
  h: Hangar,
  i: Int,
) -> Option(builder.Chassis) {
  option.then(at(spare_chassis(model.profile, h.designs), i), fn(name) {
    option.from_result(blueprint.chassis(name))
  })
}

/// A design's room, like a robot's tab in a run: the robot, the
/// fabricator's spare components and chassis. Install, remove, swap,
/// rebuild on another chassis, or sell a spare.
pub fn design_room(model: Model, h: Hangar) -> Element(Msg) {
  let s = model.scale
  let d = room(h)
  let spares = spare_parts(model.profile, h.designs)
  let #(installed, spare) = case h.pick {
    PickGarage(installed, spare) -> #(installed, spare)
    _ -> #(None, None)
  }
  let robot = case design_bot(d) {
    Some(bot) ->
      html.div([attribute.class("robot")], [
        text("ally", bot_line(s, bot)),
        ..list.flatten([
          design_lines(d),
          [
            button_class(
              "    " <> own_chassis_line(s, bot),
              picked(h.pick == PickDesignChassis),
              HangarOwnChassis,
            ),
          ],
          by_kind(bot.parts)
            |> list.map(fn(pair) {
              let #(i, c) = pair
              button_class(
                "    " <> part_line(s, c),
                picked(installed == Some(i)),
                HangarInstalled(i),
              )
            }),
          [design_status(model, d)],
        ])
      ])
    None -> text("foe", "  " <> d.name <> ": unknown chassis")
  }
  let chosen_chassis = case h.pick {
    PickSpareChassis(i) -> Some(i)
    _ -> None
  }
  let chassis_rows = fabricator_chassis_rows(model, h, chosen_chassis)
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
        case at(spare_chassis(model.profile, h.designs), i) {
          Some(name) -> [sell_button(ChassisBlueprint(name))]
          None -> []
        },
      ])
    _ -> []
  }
  // What a rebuild would do.
  let check = case h.pick {
    PickSpareChassis(i) ->
      case spare_chassis_at(model, h, i) {
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
          preview_section(model, "OUT", o),
          preview_section(model, "IN", n),
        ]
        Some(o), None -> [preview_section(model, "", o)]
        None, Some(n) -> [preview_section(model, "", n)]
        None, None -> []
      }
    PickSpareChassis(i) ->
      case spare_chassis_at(model, h, i) {
        Some(c) -> [preview_section(model, "CHASSIS", builder.body(c))]
        None -> []
      }
    PickDesignChassis ->
      case blueprint.chassis(d.chassis) {
        Ok(c) -> [preview_section(model, "", builder.body(c))]
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
        fabricator_spare_rows(model, h, option.values([spare])),
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
pub fn new_design_room(model: Model, h: Hangar) -> Element(Msg) {
  let p = model.profile
  let spares = spare_parts(p, h.designs)
  let #(chassis, drafted) = case h.pick {
    PickDraft(c, parts) -> #(Some(c), parts)
    _ -> #(None, [])
  }
  let room_left = list.length(h.designs) < p.fabricator
  let chassis_rows = fabricator_chassis_rows(model, h, chassis)
  let #(actions, check) = case h.pick, room_left {
    PickDraft(c, parts), True -> {
      let attempt =
        option.map(spare_chassis_at(model, h, c), fn(frame) {
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
        case spare_chassis_at(model, h, c) {
          Some(frame) -> [
            preview_section(model, "CHASSIS", builder.body(frame)),
          ]
          None -> []
        },
        case list.last(parts) {
          Ok(j) ->
            case at(spares, j) {
              Some(part) -> [preview_section(model, "PART", part)]
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
      html.div(
        [attribute.class("table")],
        fabricator_spare_rows(model, h, drafted),
      ),
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
