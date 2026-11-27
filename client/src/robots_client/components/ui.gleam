//// Small building blocks: buttons, text lines, tab rows.

import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import robots_client/model.{type Msg, HangarSelect, NoHangarPick}

pub fn button(label: String, msg: Msg) -> Element(Msg) {
  html.button([attribute.class("card"), event.on_click(msg)], [
    element.text(label),
  ])
}

pub fn button_class(label: String, class: String, msg: Msg) -> Element(Msg) {
  html.button([attribute.class("card " <> class), event.on_click(msg)], [
    element.text(label),
  ])
}

pub fn text(class: String, content: String) -> Element(Msg) {
  html.pre([attribute.class(class)], [element.text(content)])
}

pub fn picked(yes: Bool) -> String {
  case yes {
    True -> "picked"
    False -> ""
  }
}

/// A row of tabs at the top of a screen: (label, active, message).
pub fn tabs(items: List(#(String, Bool, Msg))) -> Element(Msg) {
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

pub fn with_cancel(actions: List(Element(Msg))) -> List(Element(Msg)) {
  case actions {
    [] -> []
    _ -> list.append(actions, [button("[Cancel]", HangarSelect(NoHangarPick))])
  }
}
