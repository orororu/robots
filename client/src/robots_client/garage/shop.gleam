//// The repair shop: the Buy and Sell tabs, then the garage's tabs (where
//// robots are repaired, modified and assembled).

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

import robots/rules/scale
import robots/run/price
import robots/run/shop
import robots/run/state
import robots_client/common/kinds.{chassis_table, part_table, robot_table}
import robots_client/common/ui.{button, button_class, picked, text}
import robots_client/common/wording.{robot_title}
import robots_client/garage/model.{
  type Msg, Buy, BuyTab, Cancel, ClickChassis, ClickForSale, ClickSpare, ForSale,
  Leave, Picked, SellPicked, SellTab, SpareChassis, StockPart, StockRobot,
}
import robots_client/garage/view.{
  type GarageView, garage_tabs, view_garage, view_selected,
}

pub fn view_shop(g: GarageView) -> Element(Msg) {
  let leave = button_class(">>> Leave", "banner", Leave)
  case g.tab {
    BuyTab -> html.div([], [garage_tabs(g), view_buy(g), leave])
    SellTab -> html.div([], [garage_tabs(g), view_sell(g), leave])
    _ -> html.div([], [view_garage(g), leave])
  }
}

/// What the shop sells: new parts and used robots. Select one to see its
/// cards, then buy it.
pub fn view_buy(g: GarageView) -> Element(Msg) {
  let run = g.run
  let parts = case run.shop.parts {
    [] -> []
    stock -> [
      text("", "PARTS · new"),
      part_table(g.scale, stock, "Price", shop.part_price, fn(i) {
        #(g.pick == ForSale(StockPart, i), ClickForSale(StockPart, i))
      }),
    ]
  }
  let robots = case run.shop.robots {
    [] -> []
    stock -> [
      text("", "ROBOTS · used"),
      ..list.index_map(stock, fn(o, i) {
        let bot = state.Bot(name: o.name, chassis: o.chassis, parts: o.parts)
        let selected = g.pick == ForSale(StockRobot, i)
        let select = #(selected, ClickForSale(StockRobot, i))
        html.div([attribute.class("robot")], [
          button_class(
            robot_title(g.scale, bot) <> " · " <> scrap(shop.robot_price(o)),
            "ally " <> picked(selected),
            ClickForSale(StockRobot, i),
          ),
          robot_table(g.scale, bot, select, fn(_) { select }),
        ])
      })
    ]
  }
  let cost = case g.pick {
    ForSale(StockPart, i) ->
      list.drop(run.shop.parts, i) |> list.first |> result.map(shop.part_price)
    ForSale(StockRobot, i) ->
      list.drop(run.shop.robots, i)
      |> list.first
      |> result.map(shop.robot_price)
    _ -> Error(Nil)
  }
  let actions = case cost {
    Ok(cost) -> [
      html.div([attribute.class("actions")], [
        button("[Buy · " <> int.to_string(cost) <> " scrap]", Buy),
        button("[Cancel]", Cancel),
      ]),
    ]
    Error(Nil) -> []
  }
  html.div([attribute.class("garage")], [
    html.div([], [
      text(
        "",
        "REPAIR SHOP · "
          <> int.to_string(price.repair(1.0) / scale.value(g.scale, 1.0))
          <> " scrap per HP · repair in each robot's tab · select something to see its cards",
      ),
      ..list.flatten([
        case parts, robots {
          [], [] -> [text("dim", "  sold out")]
          _, _ -> list.append(parts, robots)
        },
        actions,
      ])
    ]),
    view_selected(g),
  ])
}

/// Sell spare parts and chassis for half their price. Select one to see its
/// cards, then sell it.
pub fn view_sell(g: GarageView) -> Element(Msg) {
  let run = g.run
  let parts = case run.parts {
    [] -> []
    spares -> [
      text("", "SPARE PARTS"),
      part_table(g.scale, spares, "Sells for", price.sell, fn(i) {
        #(g.pick == Picked(None, Some(i)), ClickSpare(i))
      }),
    ]
  }
  let chassis = case run.chassis {
    [] -> []
    spares -> [
      text("", "SPARE CHASSIS"),
      chassis_table(
        g.scale,
        list.index_map(spares, fn(c, i) { #(i, c) }),
        "Sells for",
        price.sell_chassis,
        fn(i) { #(g.pick == SpareChassis(i), ClickChassis(i)) },
      ),
    ]
  }
  // What the shop pays for the selected spare.
  let offer = case g.pick {
    Picked(None, Some(i)) ->
      list.drop(run.parts, i) |> list.first |> result.map(price.sell)
    SpareChassis(i) ->
      list.drop(run.chassis, i) |> list.first |> result.map(price.sell_chassis)
    _ -> Error(Nil)
  }
  let actions = case offer {
    Ok(paid) -> [
      html.div([attribute.class("actions")], [
        button("[Sell · +" <> int.to_string(paid) <> " scrap]", SellPicked),
        button("[Cancel]", Cancel),
      ]),
    ]
    Error(Nil) -> []
  }
  html.div([attribute.class("garage")], [
    html.div([], [
      text("", "SELL · spare parts and chassis, for half their price"),
      ..list.flatten([
        case parts, chassis {
          [], [] -> [text("dim", "  nothing spare to sell")]
          _, _ -> list.append(parts, chassis)
        },
        actions,
      ])
    ]),
    view_selected(g),
  ])
}

fn scrap(amount: Int) -> String {
  int.to_string(amount) <> " scrap"
}
