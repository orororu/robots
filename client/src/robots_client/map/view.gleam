//// The level's map: an SVG of nodes and links, where the player picks the
//// next node.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event
import robots/rules/scale.{type Scale}
import robots/run/map
import robots/run/state.{type Run}
import robots_client/common/preview.{view_upgrade}
import robots_client/common/ui.{button_class, text}
import robots_client/common/wording.{bot_line}
import robots_client/map/model.{type Journal, type Msg, Go}

pub fn view_map(run: Run, j: Journal, s: Scale) -> Element(Msg) {
  let choices = state.choices(run)
  html.div([], [
    text("news", j.news),
    view_upgrade(s, j.upgraded),
    text(
      "",
      "MAP · level "
        <> int.to_string(run.level)
        <> " · start at the top, the boss waits at the bottom",
    ),
    map_svg(run, choices),
    text(
      "dim",
      "E enemy · S strong enemy · R repair shop · U workshop · B boss · green: your path · yellow: where you can go · faded: out of reach",
    ),
    text("", "WHERE NEXT"),
    html.div(
      [attribute.class("table")],
      list.map(choices, fn(n) {
        button_class(
          "→ " <> node_label(n) <> node_detail(n),
          "choice",
          Go(n.id),
        )
      }),
    ),
    text("", "YOUR ROBOTS · change parts in the garage before a fight"),
    html.div(
      [attribute.class("table")],
      list.map(run.robots, fn(bot) { text("ally", "  " <> bot_line(s, bot)) }),
    ),
  ])
}

pub const map_width = 760

pub const row_height = 84

pub const map_top = 30

pub fn node_xy(m: map.Map, node: map.Node) -> #(Int, Int) {
  let row = map.row(m, node.row)
  let index =
    list.index_fold(row, 0, fn(found, n, i) {
      case n.id == node.id {
        True -> i
        False -> found
      }
    })
  let x = { index + 1 } * map_width / { list.length(row) + 1 }
  #(x, map_top + node.row * row_height)
}

pub fn map_svg(run: Run, choices: List(map.Node)) -> Element(Msg) {
  let m = run.map
  let choice_ids = list.map(choices, fn(n) { n.id })
  // What can still be reached from here.
  let reachable = case run.at {
    None -> map.reachable(m, map.start(m))
    Some(id) ->
      case map.node(m, id) {
        Ok(here) -> map.reachable(m, [here])
        Error(Nil) -> []
      }
  }
  let steps = list.window_by_2(run.path)
  let links =
    list.flat_map(m.nodes, fn(from) {
      list.filter_map(from.next, fn(to_id) {
        case map.node(m, to_id) {
          Ok(to) -> Ok(link(m, run, from, to, steps, choice_ids, reachable))
          Error(Nil) -> Error(Nil)
        }
      })
    })
  let nodes =
    list.map(m.nodes, fn(n) { map_node(m, run, n, choice_ids, reachable) })
  svg.svg(
    [
      attribute.attribute(
        "viewBox",
        "0 0 "
          <> int.to_string(map_width)
          <> " "
          <> int.to_string(map_top * 2 + map.rows * row_height + 20),
      ),
      attribute.class("map"),
    ],
    list.append(links, nodes),
  )
}

pub fn link(
  m: map.Map,
  run: Run,
  from: map.Node,
  to: map.Node,
  steps: List(#(Int, Int)),
  choice_ids: List(Int),
  reachable: List(Int),
) -> Element(Msg) {
  let #(x1, y1) = node_xy(m, from)
  let #(x2, y2) = node_xy(m, to)
  let #(color, width) = case
    list.contains(steps, #(from.id, to.id)),
    run.at == Some(from.id) && list.contains(choice_ids, to.id),
    list.contains(reachable, from.id) && list.contains(reachable, to.id)
  {
    True, _, _ -> #("#8fd18f", "3")
    _, True, _ -> #("#f0d060", "3")
    _, _, True -> #("#6a766a", "1.5")
    _, _, False -> #("#2a302a", "1")
  }
  svg.line([
    attribute.attribute("x1", int.to_string(x1)),
    attribute.attribute("y1", int.to_string(y1)),
    attribute.attribute("x2", int.to_string(x2)),
    attribute.attribute("y2", int.to_string(y2)),
    attribute.attribute("stroke", color),
    attribute.attribute("stroke-width", width),
  ])
}

pub fn map_node(
  m: map.Map,
  run: Run,
  node: map.Node,
  choice_ids: List(Int),
  reachable: List(Int),
) -> Element(Msg) {
  let #(x, y) = node_xy(m, node)
  let #(letter, fill, stroke) = case node.event {
    map.RepairShop -> #("R", "#1f3340", "#7ab0d0")
    map.Workshop -> #("U", "#2a3a1f", "#a8d07a")
    map.Battle(tier: map.Normal, ..) -> #("E", "#33241f", "#e08a7a")
    map.Battle(tier: map.Strong, ..) -> #("S", "#4a1c1c", "#ff6a5a")
    map.Battle(tier: map.Boss, ..) -> #("B", "#3a2048", "#c890f0")
  }
  let here = run.at == Some(node.id)
  let visited = list.contains(run.path, node.id)
  let choice = list.contains(choice_ids, node.id)
  let #(stroke, stroke_width) = case here, choice {
    True, _ -> #("#8fd18f", "4")
    _, True -> #("#f0d060", "3")
    _, _ -> #(stroke, "1.5")
  }
  let opacity = case here || visited || list.contains(reachable, node.id) {
    True -> "1"
    False -> "0.25"
  }
  let fill = case visited && !here {
    True -> "#22331f"
    False -> fill
  }
  let lines = label_lines(node_label(node))
  let events = case choice {
    True -> [event.on_click(Go(node.id)), attribute.class("clickable")]
    False -> []
  }
  svg.g([attribute.attribute("opacity", opacity), ..events], [
    svg.title([], [element.text(node_label(node) <> node_detail(node))]),
    svg.circle([
      attribute.attribute("cx", int.to_string(x)),
      attribute.attribute("cy", int.to_string(y)),
      attribute.attribute("r", "15"),
      attribute.attribute("fill", fill),
      attribute.attribute("stroke", stroke),
      attribute.attribute("stroke-width", stroke_width),
    ]),
    svg_text(x, y + 5, "14", "#e8ece8", letter),
    ..list.index_map(lines, fn(line, i) {
      svg_text(x, y + 30 + i * 12, "11", "#b8c0b8", line)
    })
  ])
}

pub fn svg_text(
  x: Int,
  y: Int,
  size: String,
  color: String,
  content: String,
) -> Element(Msg) {
  svg.text(
    [
      attribute.attribute("x", int.to_string(x)),
      attribute.attribute("y", int.to_string(y)),
      attribute.attribute("font-size", size),
      attribute.attribute("fill", color),
      attribute.attribute("text-anchor", "middle"),
    ],
    content,
  )
}

/// A node's name in at most two short lines.
pub fn label_lines(label: String) -> List(String) {
  case string.length(label) <= 20 {
    True -> [label]
    False -> {
      let words = string.split(label, " ")
      let half = list.length(words) / 2
      [
        string.join(list.take(words, half), " "),
        string.join(list.drop(words, half), " "),
      ]
    }
  }
}

/// " · A small, quick scrapper..." for battles.
pub fn node_detail(node: map.Node) -> String {
  case node.event {
    map.Battle(enemy:, ..) -> " · " <> enemy.description
    map.RepairShop -> " · repair your robots for scrap"
    map.Workshop -> " · upgrade one component, free"
  }
}

pub fn node_label(node: map.Node) -> String {
  case node.event {
    map.RepairShop -> "Repair shop"
    map.Workshop -> "Workshop"
    map.Battle(tier: map.Normal, enemy:) -> enemy.name
    map.Battle(tier: map.Strong, enemy:) -> "STRONG " <> enemy.name
    map.Battle(tier: map.Boss, enemy:) -> "BOSS " <> enemy.name
  }
}
