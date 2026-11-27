//// The run's garage: a tab per robot (modify it, rebuild it on a spare
//// chassis), a New robot tab, the shared spare parts and what's selected.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/builder
import robots/construction/part
import robots/rules/scale

import robots/run/state
import robots/run/upgrade
import robots_client/components/preview.{preview_section}
import robots_client/components/ui.{button, button_class, picked, tabs, text}
import robots_client/model.{
  type Model, type Msg, type Pick, Assemble, Cancel, ClickChassis,
  ClickInstalled, ClickOwnChassis, ClickSpare, Draft, ForSale, GoTab, Install,
  NewRobotTab, OwnChassis, Picked, Rebuild, Remove, RepairPicked, RobotTab,
  ShopTab, SpareChassis, StockPart, StockRobot, Swap, UpgradePicked, at_shop,
  current_tab, repair_target, upgrade_target,
}
import robots_client/wording.{
  bot_line, by_kind, describe_error, kind_plural, mounts_line, num, offer_deck,
  own_chassis_line, part_line, weight_line,
}

/// Shop (at a shop) | a tab per robot | + New robot.
pub fn garage_tabs(model: Model) -> Element(Msg) {
  let open = current_tab(model)
  tabs(
    list.flatten([
      case at_shop(model) {
        True -> [#("Shop", open == ShopTab, GoTab(ShopTab))]
        False -> []
      },
      list.index_map(model.run.robots, fn(bot, r) {
        #(bot.name, open == RobotTab(r), GoTab(RobotTab(r)))
      }),
      [#("+ New robot", open == NewRobotTab, GoTab(NewRobotTab))],
    ]),
  )
}

/// The garage: a tab per robot, where it's modified or rebuilt on another
/// chassis, and one to assemble a new robot from a spare chassis. The
/// spare parts are shared.
pub fn view_garage(model: Model) -> Element(Msg) {
  html.div([], [
    garage_tabs(model),
    case current_tab(model) {
      RobotTab(r) -> robot_room(model, r)
      NewRobotTab | ShopTab -> new_robot_room(model)
    },
  ])
}

/// Spare parts grouped by kind, a heading per kind; `chosen` are shown
/// as selected.
pub fn spare_rows(model: Model, chosen: List(Int)) -> List(Element(Msg)) {
  let rows =
    by_kind(model.run.parts)
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "  " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let #(i, p) = pair
          button_class(
            "    " <> part_line(model.scale, p),
            picked(list.contains(chosen, i)),
            ClickSpare(i),
          )
        })
      ]
    })
  case rows {
    [] -> [text("dim", "  none")]
    _ -> rows
  }
}

pub fn chassis_rows(model: Model, chosen: Option(Int)) -> List(Element(Msg)) {
  list.index_map(model.run.chassis, fn(c, i) {
    button_class(
      "  "
        <> c.name
        <> " chassis · "
        <> int.to_string(scale.value(model.scale, builder.chassis_hp(c)))
        <> " HP · max weight "
        <> num(c.capacity)
        <> " · weapon mounts up to "
        <> string.join(
        list.map(builder.mounts(c, []), fn(m) { num(m.0) }),
        ", ",
      ),
      picked(chosen == Some(i)),
      ClickChassis(i),
    )
  })
}

/// Repair (at a shop) and upgrade (at a workshop) for what's selected.
pub fn service_actions(model: Model) -> List(Element(Msg)) {
  let run = model.run
  let repair = case at_shop(model), repair_target(model.pick) {
    True, Some(target) ->
      case state.repair_one_price(run, target) {
        Ok(cost) if cost > 0 -> [
          button("[Repair · " <> int.to_string(cost) <> " scrap]", RepairPicked),
        ]
        _ -> []
      }
    _, _ -> []
  }
  let upgrade = case run.phase, upgrade_target(model.pick) {
    state.Upgrading(_), Some(target) ->
      case state.target_part(run, target) {
        Ok(p) ->
          case upgrade.can_upgrade(p) {
            True -> [button("[Upgrade]", UpgradePicked)]
            False -> [text("dim", "  every card is at its best")]
          }
        Error(_) -> []
      }
    _, _ -> []
  }
  list.append(upgrade, repair)
}

pub fn with_cancel_run(
  actions: List(Element(Msg)),
  pick: Pick,
) -> List(Element(Msg)) {
  case pick {
    Picked(None, None) -> []
    _ -> list.append(actions, [button("[Cancel]", Cancel)])
  }
}

/// One robot's room: the robot, the shared spare parts, and spare chassis
/// to rebuild it on.
pub fn robot_room(model: Model, r: Int) -> Element(Msg) {
  let run = model.run
  let assert [bot, ..] = list.drop(run.robots, r)
  let #(installed, spare) = case model.pick {
    Picked(installed, spare) -> #(installed, spare)
    _ -> #(None, None)
  }
  let robot =
    html.div([attribute.class("robot")], [
      text("ally", bot_line(model.scale, bot)),
      text("", "    " <> weight_line(bot)),
      text("", "    " <> mounts_line(bot)),
      button_class(
        "    " <> own_chassis_line(model.scale, bot),
        picked(model.pick == OwnChassis(r)),
        ClickOwnChassis(r),
      ),
      ..by_kind(bot.parts)
      |> list.map(fn(pair) {
        let #(i, p) = pair
        button_class(
          "    " <> part_line(model.scale, p),
          picked(installed == Some(#(r, i))),
          ClickInstalled(r, i),
        )
      })
    ])
  let chosen_chassis = case model.pick {
    SpareChassis(c) -> Some(c)
    _ -> None
  }
  let actions = case model.pick {
    Picked(Some(#(pr, _)), Some(_)) if pr == r -> [button("[Swap them]", Swap)]
    Picked(Some(#(pr, _)), None) if pr == r -> [button("[Remove part]", Remove)]
    Picked(None, Some(_)) -> [
      button("[Install on " <> bot.name <> "]", Install(r)),
    ]
    SpareChassis(_) -> [button("[Rebuild " <> bot.name <> " on it]", Rebuild)]
    _ -> []
  }
  let actions =
    list.append(service_actions(model), actions)
    |> with_cancel_run(model.pick)
  let chassis = chassis_rows(model, chosen_chassis)
  html.div([attribute.class("garage")], [
    html.div([], [
      text("", bot.name <> " · " <> hint(model.pick)),
      html.div([attribute.class("table")], [robot]),
      text("", "SPARE PARTS"),
      html.div(
        [attribute.class("table")],
        spare_rows(model, option.values([spare])),
      ),
      case chassis {
        [] -> text("", "")
        _ ->
          html.div([attribute.class("table")], [
            text("", "SPARE CHASSIS · rebuild " <> bot.name <> " on one"),
            ..chassis
          ])
      },
      html.div([attribute.class("actions")], actions),
      ..fit_lines(model)
    ]),
    view_selected(model),
  ])
}

/// Assemble a new robot: a spare chassis and spare parts.
pub fn new_robot_room(model: Model) -> Element(Msg) {
  let run = model.run
  let #(chassis, drafted) = case model.pick {
    Draft(c, parts, _) -> #(Some(c), parts)
    _ -> #(None, [])
  }
  let room = list.length(run.robots) < run.truck
  let actions = case model.pick {
    Draft(..) -> [button("[Assemble robot]", Assemble)]
    _ -> []
  }
  let actions =
    list.append(service_actions(model), actions)
    |> with_cancel_run(model.pick)
  html.div([attribute.class("garage")], [
    html.div([], [
      text(
        "",
        "NEW ROBOT · "
          <> case room, run.chassis {
          False, _ ->
            "the truck is full ("
            <> int.to_string(run.truck)
            <> " robots): a spare chassis waits"
          True, [] -> "no spare chassis: win or buy one"
          True, _ ->
            case chassis {
              None -> "select a spare chassis to build on"
              Some(_) -> "select spare parts for it, then assemble"
            }
        },
      ),
      html.div([attribute.class("table")], [
        text("", "SPARE CHASSIS"),
        ..case run.chassis {
          [] -> [text("dim", "  none")]
          _ -> chassis_rows(model, chassis)
        }
      ]),
      text("", "SPARE PARTS"),
      html.div(
        [attribute.class("table")],
        spare_rows(model, case model.pick {
          Draft(..) -> drafted
          Picked(_, spare) -> option.values([spare])
          _ -> []
        }),
      ),
      html.div([attribute.class("actions")], actions),
      ..fit_lines(model)
    ]),
    view_selected(model),
  ])
}

/// The cards of what's selected: an installed part, a spare, both (what
/// goes out and what comes in), or a chassis being built on.
pub fn view_selected(model: Model) -> Element(Msg) {
  let run = model.run
  let installed_part = fn(r, i) {
    case list.drop(run.robots, r) {
      [bot, ..] -> list.drop(bot.parts, i) |> list.first |> option.from_result
      [] -> None
    }
  }
  let spare_part = fn(i) {
    list.drop(run.parts, i) |> list.first |> option.from_result
  }
  let sections = case model.pick {
    Picked(installed, spare) -> {
      let out =
        option.then(installed, fn(pair) { installed_part(pair.0, pair.1) })
      let incoming = option.then(spare, spare_part)
      case out, incoming {
        Some(o), Some(n) -> [
          preview_section(model, "OUT", o),
          preview_section(model, "IN", n),
        ]
        Some(o), None -> [preview_section(model, "", o)]
        None, Some(n) -> [preview_section(model, "", n)]
        None, None -> [
          text("dim", "Select a part, spare or chassis to see its cards."),
        ]
      }
    }
    Draft(chassis, _, last) -> {
      let body =
        list.drop(run.chassis, chassis)
        |> list.first
        |> option.from_result
        |> option.map(builder.body)
      list.flatten([
        case body {
          Some(b) -> [preview_section(model, "CHASSIS", b)]
          None -> []
        },
        case option.then(last, spare_part) {
          Some(p) -> [preview_section(model, "PART", p)]
          None -> []
        },
      ])
    }
    ForSale(StockPart, i) ->
      case list.drop(run.shop.parts, i) {
        [p, ..] -> [preview_section(model, "FOR SALE", p)]
        [] -> []
      }
    ForSale(StockRobot, i) ->
      case list.drop(run.shop.robots, i) {
        [o, ..] -> [
          text("", "FOR SALE: " <> o.name <> " · " <> offer_deck(o)),
          preview_section(model, "CHASSIS", builder.body(o.chassis)),
          ..list.map(o.parts, preview_section(model, "PART", _))
        ]
        [] -> []
      }
    OwnChassis(r) ->
      case list.drop(run.robots, r) {
        [bot, ..] -> [preview_section(model, "", builder.body(bot.chassis))]
        [] -> []
      }
    SpareChassis(c) ->
      case list.drop(run.chassis, c) {
        [frame, ..] -> [preview_section(model, "CHASSIS", builder.body(frame))]
        [] -> []
      }
  }
  html.div([attribute.class("preview")], sections)
}

pub fn hint(pick: Pick) -> String {
  case pick {
    Picked(None, None) ->
      "select a part or spare to see its cards; a spare chassis to rebuild on"
    Picked(Some(_), None) -> "remove it, or select a spare to swap it for"
    Picked(None, Some(_)) -> "install it, or select an installed part to swap"
    Picked(Some(_), Some(_)) -> "swap them, or change either selection"
    Draft(..) -> "select spare parts for the new robot, then assemble"
    OwnChassis(_) -> "the chassis' own cards; it can be repaired at a shop"
    ForSale(..) -> "on sale: buy it above, or select something else"
    SpareChassis(_) -> "rebuild the robot on it: the parts that fit move over"
  }
}

/// What the selected change would do to each robot it could apply to:
/// "✓ fits on Tinker" or "✗ Tinker: Too heavy: 14, max weight 12".
pub fn fit_lines(model: Model) -> List(Element(Msg)) {
  let run = model.run
  let line = fn(name, result) {
    case result {
      Ok(_) -> text("ally", "✓ " <> name)
      Error(e) -> text("foe", "✗ " <> describe_error(e))
    }
  }
  case model.pick {
    Picked(None, Some(spare)) ->
      case current_tab(model) {
        RobotTab(r) ->
          case list.drop(run.robots, r) {
            [bot, ..] -> [
              line("fits on " <> bot.name, state.install(run, r, spare)),
            ]
            [] -> []
          }
        _ -> []
      }
    SpareChassis(c) ->
      case current_tab(model) {
        RobotTab(r) ->
          case state.rebuild(run, r, c) {
            Ok(#(_, [])) -> [text("ally", "✓ every part fits")]
            Ok(#(_, dropped)) -> [
              text(
                "ally",
                "✓ it works · to the spares: "
                  <> string.join(list.map(dropped, part.display_name), ", "),
              ),
            ]
            Error(e) -> [text("foe", "✗ " <> describe_error(e))]
          }
        _ -> []
      }
    Draft(chassis, parts, _) -> [
      line("it can be built", state.assemble(run, "New", chassis, parts)),
    ]
    Picked(Some(#(r, i)), Some(spare)) -> [
      line("the swap works", state.swap(run, r, i, spare)),
    ]
    Picked(Some(#(r, i)), None) -> [
      line("it can be removed", state.uninstall(run, r, i)),
    ]
    _ -> []
  }
}
