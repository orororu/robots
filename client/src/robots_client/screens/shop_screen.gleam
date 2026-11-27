//// The repair shop: the Shop tab (repair, buy, sell) and the garage tabs.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/part
import robots/rules/scale
import robots/run/price
import robots/run/shop
import robots/run/state
import robots_client/components/garage.{garage_tabs, view_garage, view_selected}
import robots_client/components/ui.{button, button_class, text}
import robots_client/model.{
  type Model, type Msg, Buy, Cancel, ClickForSale, ClickSpare, ForSale, Leave,
  Picked, Repair, SellPicked, ShopTab, StockPart, StockRobot, current_tab,
}
import robots_client/wording.{bot_line, by_kind, kind_plural, part_line}

pub fn view_shop(model: Model) -> Element(Msg) {
  case current_tab(model) {
    ShopTab -> html.div([], [garage_tabs(model), view_counter(model)])
    _ ->
      html.div([], [
        view_garage(model),
        button_class(">>> Leave", "banner", Leave),
      ])
  }
}

/// The shop's counter: repair the robots, buy, sell spare parts. The
/// garage (installing, swapping, assembling) is its own screen.
pub fn view_counter(model: Model) -> Element(Msg) {
  let run = model.run
  let s = model.scale
  let robots =
    list.index_map(run.robots, fn(bot, r) {
      case state.repair_price(bot) {
        0 -> text("dim", "  " <> bot_line(s, bot) <> " · as new")
        cost ->
          button(
            "  Repair all of "
              <> bot_line(s, bot)
              <> " · "
              <> int.to_string(cost)
              <> " scrap",
            Repair(r),
          )
      }
    })
  let selling = case model.pick {
    Picked(None, Some(i)) -> Some(i)
    _ -> None
  }
  let spares =
    by_kind(run.parts)
    |> list.chunk(fn(pair) { { pair.1 }.kind })
    |> list.flat_map(fn(group) {
      let assert [#(_, first), ..] = group
      [
        text("dim", "  " <> string.uppercase(kind_plural(first.kind))),
        ..list.map(group, fn(pair) {
          let #(i, p) = pair
          button_class(
            "    "
              <> part_line(s, p)
              <> " · sells for "
              <> int.to_string(price.sell(p)),
            case selling == Some(i) {
              True -> "picked"
              False -> ""
            },
            ClickSpare(i),
          )
        })
      ]
    })
  let sell_actions = case selling {
    Some(i) ->
      case list.drop(run.parts, i) {
        [p, ..] -> [
          html.div([attribute.class("actions")], [
            button(
              "[Sell · +" <> int.to_string(price.sell(p)) <> " scrap]",
              SellPicked,
            ),
            button("[Cancel]", Cancel),
          ]),
        ]
        [] -> []
      }
    None -> []
  }
  html.div([], [
    text(
      "",
      "REPAIR SHOP · "
        <> int.to_string(price.repair(1.0) / scale.value(s, 1.0))
        <> " scrap per HP · repair one part or chassis in the Garage tab",
    ),
    html.div([attribute.class("table")], robots),
    html.div([attribute.class("garage")], [
      html.div([], [
        view_stock(model),
        text("", "SELL · your spare parts; select one to see its cards"),
        html.div([attribute.class("table")], case spares {
          [] -> [text("dim", "  none")]
          _ -> spares
        }),
        ..sell_actions
      ]),
      view_selected(model),
    ]),
    button_class(">>> Leave", "banner", Leave),
  ])
}

/// What the shop sells, by kind; select one to see its cards, then buy it.
pub fn view_stock(model: Model) -> Element(Msg) {
  let run = model.run
  let s = model.scale
  let item = fn(label, stock, i) {
    button_class(
      "    " <> label,
      case model.pick == ForSale(stock, i) {
        True -> "picked"
        False -> ""
      },
      ClickForSale(stock, i),
    )
  }
  let group = fn(title, items) {
    case items {
      [] -> []
      _ -> [text("dim", "  " <> title), ..items]
    }
  }
  let parts =
    by_kind(run.shop.parts)
    |> list.map(fn(pair) {
      let #(i, p) = pair
      item(part_line(s, p), StockPart, i)
    })
  let robots =
    list.index_map(run.shop.robots, fn(o, i) {
      item(
        "Used "
          <> o.name
          <> " ("
          <> o.chassis.name
          <> ") · "
          <> string.join(list.map(o.parts, part.display_name), ", ")
          <> " · "
          <> int.to_string(shop.robot_price(o))
          <> " scrap",
        StockRobot,
        i,
      )
    })
  let price_of = case model.pick {
    ForSale(StockPart, i) ->
      list.drop(run.shop.parts, i) |> list.first |> result.map(shop.part_price)
    ForSale(StockRobot, i) ->
      list.drop(run.shop.robots, i)
      |> list.first
      |> result.map(shop.robot_price)
    _ -> Error(Nil)
  }
  let actions = case price_of {
    Ok(cost) -> [
      html.div([attribute.class("actions")], [
        button("[Buy · " <> int.to_string(cost) <> " scrap]", Buy),
        button("[Cancel]", Cancel),
      ]),
    ]
    Error(Nil) -> []
  }
  let rows =
    list.flatten([
      group("PARTS (new)", parts),
      group("ROBOTS (used)", robots),
    ])
  html.div([], [
    text("", "FOR SALE · select something to see its cards"),
    html.div([attribute.class("table")], case rows {
      [] -> [text("dim", "  sold out")]
      _ -> rows
    }),
    ..actions
  ])
}
