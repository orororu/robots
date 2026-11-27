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
import robots/rules/scale.{type Scale}

import robots/run/state.{type Run}
import robots/run/upgrade
import robots_client/common/kinds.{robot_table, spare_table}
import robots_client/common/preview.{preview_section}
import robots_client/common/ui.{button, button_class, picked, tabs, text}
import robots_client/common/wording.{
  describe_error, num, offer_deck, robot_title,
}
import robots_client/garage/model.{
  type Garage, type Msg, type Pick, type Tab, Assemble, BuyTab, Cancel,
  ClickChassis, ClickInstalled, ClickOwnChassis, ClickSpare, Draft, ForSale,
  GoTab, Install, NewRobotTab, OwnChassis, Picked, Rebuild, Remove, Repair,
  RepairPicked, RobotTab, SellTab, SpareChassis, StockPart, StockRobot, Swap,
  UpgradePicked, at_shop, current_tab, repair_target, upgrade_target,
}

/// What the garage shows: the run, what's selected, the open tab (made
/// valid, see `model.current_tab`) and the display scale.
pub type GarageView {
  GarageView(run: Run, pick: Pick, tab: Tab, scale: Scale)
}

pub fn view_of(run: Run, garage: Garage, scale: Scale) -> GarageView {
  GarageView(run:, pick: garage.pick, tab: current_tab(run, garage.tab), scale:)
}

/// Buy | Sell (at a shop) | a tab per robot | + New robot.
pub fn garage_tabs(g: GarageView) -> Element(Msg) {
  let open = g.tab
  tabs(
    list.flatten([
      case at_shop(g.run) {
        True -> [
          #("Buy", open == BuyTab, GoTab(BuyTab)),
          #("Sell", open == SellTab, GoTab(SellTab)),
        ]
        False -> []
      },
      list.index_map(g.run.robots, fn(bot, r) {
        #(bot.name, open == RobotTab(r), GoTab(RobotTab(r)))
      }),
      [#("+ New robot", open == NewRobotTab, GoTab(NewRobotTab))],
    ]),
  )
}

/// The garage: a tab per robot, where it's modified or rebuilt on another
/// chassis, and one to assemble a new robot from a spare chassis. The
/// spare parts are shared.
pub fn view_garage(g: GarageView) -> Element(Msg) {
  html.div([], [
    garage_tabs(g),
    case g.tab {
      RobotTab(r) -> robot_room(g, r)
      NewRobotTab | BuyTab | SellTab -> new_robot_room(g)
    },
  ])
}

/// Spare parts in a table grouped by kind; `chosen` are shown as selected.
pub fn spare_rows(g: GarageView, chosen: List(Int)) -> List(Element(Msg)) {
  case g.run.parts {
    [] -> [text("dim", "  none")]
    parts -> [spare_table(g.scale, parts, chosen, ClickSpare)]
  }
}

pub fn chassis_rows(g: GarageView, chosen: Option(Int)) -> List(Element(Msg)) {
  list.index_map(g.run.chassis, fn(c, i) {
    button_class(
      "  "
        <> c.name
        <> " chassis · "
        <> int.to_string(scale.value(g.scale, builder.chassis_hp(c)))
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
pub fn service_actions(g: GarageView) -> List(Element(Msg)) {
  let run = g.run
  let repair = case at_shop(g.run), repair_target(g.pick) {
    True, Some(target) ->
      case state.repair_one_price(run, target) {
        Ok(cost) if cost > 0 -> [
          button("[Repair · " <> int.to_string(cost) <> " scrap]", RepairPicked),
        ]
        _ -> []
      }
    _, _ -> []
  }
  let upgrade = case run.phase, upgrade_target(g.pick) {
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
pub fn robot_room(g: GarageView, r: Int) -> Element(Msg) {
  let run = g.run
  let assert [bot, ..] = list.drop(run.robots, r)
  let #(installed, spare) = case g.pick {
    Picked(installed, spare) -> #(installed, spare)
    _ -> #(None, None)
  }
  let robot =
    html.div([attribute.class("robot")], [
      text("ally", robot_title(g.scale, bot)),
      robot_table(
        g.scale,
        bot,
        #(g.pick == OwnChassis(r), ClickOwnChassis(r)),
        fn(i) { #(installed == Some(#(r, i)), ClickInstalled(r, i)) },
      ),
    ])
  let chosen_chassis = case g.pick {
    SpareChassis(c) -> Some(c)
    _ -> None
  }
  let actions = case g.pick {
    Picked(Some(#(pr, _)), Some(_)) if pr == r -> [button("[Swap them]", Swap)]
    Picked(Some(#(pr, _)), None) if pr == r -> [button("[Remove part]", Remove)]
    Picked(None, Some(_)) -> [
      button("[Install on " <> bot.name <> "]", Install(r)),
    ]
    SpareChassis(_) -> [button("[Rebuild " <> bot.name <> " on it]", Rebuild)]
    _ -> []
  }
  let actions =
    list.append(service_actions(g), actions)
    |> with_cancel_run(g.pick)
  // At a shop: repair the whole robot.
  let repair_all = case at_shop(run), state.repair_price(bot) {
    False, _ -> []
    True, 0 -> [text("dim", "    as new: nothing to repair")]
    True, cost -> [
      button(
        "[Repair all of "
          <> bot.name
          <> " · "
          <> int.to_string(cost)
          <> " scrap]",
        Repair(r),
      ),
    ]
  }
  let chassis = chassis_rows(g, chosen_chassis)
  html.div([attribute.class("garage")], [
    html.div([], [
      text("", bot.name <> " · " <> hint(g.pick)),
      html.div([attribute.class("table")], [robot]),
      html.div([attribute.class("actions")], repair_all),
      text("", "SPARE PARTS"),
      html.div(
        [attribute.class("table")],
        spare_rows(g, option.values([spare])),
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
      ..fit_lines(g)
    ]),
    view_selected(g),
  ])
}

/// Assemble a new robot: a spare chassis and spare parts.
pub fn new_robot_room(g: GarageView) -> Element(Msg) {
  let run = g.run
  let #(chassis, drafted) = case g.pick {
    Draft(c, parts, _) -> #(Some(c), parts)
    _ -> #(None, [])
  }
  let room = list.length(run.robots) < run.truck
  let actions = case g.pick {
    Draft(..) -> [button("[Assemble robot]", Assemble)]
    _ -> []
  }
  let actions =
    list.append(service_actions(g), actions)
    |> with_cancel_run(g.pick)
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
          _ -> chassis_rows(g, chassis)
        }
      ]),
      text("", "SPARE PARTS"),
      html.div(
        [attribute.class("table")],
        spare_rows(g, case g.pick {
          Draft(..) -> drafted
          Picked(_, spare) -> option.values([spare])
          _ -> []
        }),
      ),
      html.div([attribute.class("actions")], actions),
      ..fit_lines(g)
    ]),
    view_selected(g),
  ])
}

/// The cards of what's selected: an installed part, a spare, both (what
/// goes out and what comes in), or a chassis being built on.
pub fn view_selected(g: GarageView) -> Element(Msg) {
  let run = g.run
  let installed_part = fn(r, i) {
    case list.drop(run.robots, r) {
      [bot, ..] -> list.drop(bot.parts, i) |> list.first |> option.from_result
      [] -> None
    }
  }
  let spare_part = fn(i) {
    list.drop(run.parts, i) |> list.first |> option.from_result
  }
  let sections = case g.pick {
    Picked(installed, spare) -> {
      let out =
        option.then(installed, fn(pair) { installed_part(pair.0, pair.1) })
      let incoming = option.then(spare, spare_part)
      case out, incoming {
        Some(o), Some(n) -> [
          preview_section(g.scale, "OUT", o),
          preview_section(g.scale, "IN", n),
        ]
        Some(o), None -> [preview_section(g.scale, "", o)]
        None, Some(n) -> [preview_section(g.scale, "", n)]
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
          Some(b) -> [preview_section(g.scale, "CHASSIS", b)]
          None -> []
        },
        case option.then(last, spare_part) {
          Some(p) -> [preview_section(g.scale, "PART", p)]
          None -> []
        },
      ])
    }
    ForSale(StockPart, i) ->
      case list.drop(run.shop.parts, i) {
        [p, ..] -> [preview_section(g.scale, "FOR SALE", p)]
        [] -> []
      }
    ForSale(StockRobot, i) ->
      case list.drop(run.shop.robots, i) {
        [o, ..] -> [
          text("", "FOR SALE: " <> o.name <> " · " <> offer_deck(o)),
          preview_section(g.scale, "CHASSIS", builder.body(o.chassis)),
          ..list.map(o.parts, preview_section(g.scale, "PART", _))
        ]
        [] -> []
      }
    OwnChassis(r) ->
      case list.drop(run.robots, r) {
        [bot, ..] -> [preview_section(g.scale, "", builder.body(bot.chassis))]
        [] -> []
      }
    SpareChassis(c) ->
      case list.drop(run.chassis, c) {
        [frame, ..] -> [
          preview_section(g.scale, "CHASSIS", builder.body(frame)),
        ]
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
pub fn fit_lines(g: GarageView) -> List(Element(Msg)) {
  let run = g.run
  let line = fn(name, result) {
    case result {
      Ok(_) -> text("ally", "✓ " <> name)
      Error(e) -> text("foe", "✗ " <> describe_error(e))
    }
  }
  case g.pick {
    Picked(None, Some(spare)) ->
      case g.tab {
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
      case g.tab {
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
