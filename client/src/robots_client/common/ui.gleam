//// Small building blocks: buttons, text lines, tab rows. They work with any
//// message type.

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
