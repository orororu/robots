//// A part's cards beside the lists, with what each attribute changes, and
//// the last workshop upgrade.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/part.{type Component}
import robots/rules/card
import robots_client/components/card_view
import robots_client/components/ui.{text}
import robots_client/model.{type Model, type Msg}

pub fn preview_section(
  model: Model,
  label: String,
  p: Component,
) -> Element(Msg) {
  let title = case label {
    "" -> ""
    _ -> label <> ": "
  }
  let cards = part.cards(p)
  html.div([], [
    text(
      "",
      title
        <> part.display_name(p)
        <> " · "
        <> case cards {
        [] -> "no cards"
        [_] -> "1 card"
        _ -> int.to_string(list.length(cards)) <> " cards"
      },
    ),
    card_view.row(
      list.index_map(list.zip(cards, part.plain_cards(p)), fn(pair, i) {
        let #(c, plain) = pair
        let shown = plain_card(model, c)
        // An attribute: what it is and what it does to the plain card.
        case part.attribute_at(p, i) {
          Ok(#(word, good)) ->
            card_view.noted(
              shown,
              word <> ": " <> card_view.change_text(model.scale, plain, c),
              good,
            )
          Error(Nil) -> shown
        }
      }),
    ),
  ])
}

pub fn plain_card(model: Model, c: card.Card) -> Element(Msg) {
  card_view.view(
    model.scale,
    c,
    current: c.value,
    key: None,
    dim: False,
    on_click: None,
    charge: None,
  )
}

/// The last upgrade: the card before and after, with what changed.
pub fn view_upgrade(model: Model) -> Element(Msg) {
  case model.upgraded {
    None -> text("", "")
    Some(#(name, change)) ->
      html.div([], [
        text(
          "",
          "UPGRADED "
            <> name
            <> ": "
            <> change.attribute
            <> " added to "
            <> change.plain.name
            <> case change.replaced {
            Some(old) -> " (replacing " <> old <> ")"
            None -> ""
          },
        ),
        card_view.row([
          card_view.noted(plain_card(model, change.before), "before", False),
          card_view.noted(
            plain_card(model, change.after),
            "after: "
              <> card_view.change_text(model.scale, change.before, change.after),
            True,
          ),
        ]),
      ])
  }
}
