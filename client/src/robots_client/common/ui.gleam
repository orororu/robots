//// Small building blocks: buttons, text lines, tab rows. They work with any
//// message type.

import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn button(label: String, msg: msg) -> Element(msg) {
  html.button([attribute.class("card"), event.on_click(msg)], [
    element.text(label),
  ])
}

pub fn button_class(label: String, class: String, msg: msg) -> Element(msg) {
  html.button([attribute.class("card " <> class), event.on_click(msg)], [
    element.text(label),
  ])
}

pub fn text(class: String, content: String) -> Element(msg) {
  html.pre([attribute.class(class)], [element.text(content)])
}

pub fn picked(yes: Bool) -> String {
  case yes {
    True -> "picked"
    False -> ""
  }
}

/// A row of tabs at the top of a screen: (label, active, message).
pub fn tabs(items: List(#(String, Bool, msg))) -> Element(msg) {
  html.div(
    [attribute.class("tabs")],
    list.map(items, fn(item) {
      let #(label, active, msg) = item
      button_class(
        label,
        case active {
          True -> "tab active"
          False -> "tab"
        },
        msg,
      )
    }),
  )
}

/// A table: a header row, then rows (`table_row`, `table_group`). The last
/// column (a price) is right-aligned.
pub fn table(headers: List(String), rows: List(Element(msg))) -> Element(msg) {
  html.table([attribute.class("list")], [
    html.thead([], [
      html.tr([], list.map(headers, fn(h) { html.th([], [element.text(h)]) })),
    ]),
    html.tbody([], rows),
  ])
}

/// A row to select: clicking it sends `msg`.
pub fn table_row(
  cells: List(String),
  selected: Bool,
  msg: msg,
) -> Element(msg) {
  html.tr(
    [attribute.class("clickable " <> picked(selected)), event.on_click(msg)],
    list.map(cells, fn(c) { html.td([], [element.text(c)]) }),
  )
}

/// A heading row across all `columns`.
pub fn table_group(title: String, columns: Int) -> Element(msg) {
  html.tr([attribute.class("group")], [
    html.td([attribute.attribute("colspan", int.to_string(columns))], [
      element.text(title),
    ]),
  ])
}

/// A row that can't be selected (an empty slot), shown dim.
pub fn table_note(cells: List(String)) -> Element(msg) {
  html.tr(
    [attribute.class("dim")],
    list.map(cells, fn(c) { html.td([], [element.text(c)]) }),
  )
}
