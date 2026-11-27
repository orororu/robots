//// A part's cards beside the lists, with what each attribute changes, and
//// the last workshop upgrade.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/element.{type Element}
import lustre/element/html
import robots/construction/part.{type Component}
import robots/rules/card
import robots/rules/scale.{type Scale}
import robots/run/upgrade
import robots_client/common/card_view
import robots_client/common/ui.{text}

pub fn preview_section(s: Scale, label: String, p: Component) -> Element(msg) {
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
        let shown = plain_card(s, c)
        // An attribute: what it is and what it does to the plain card.
        case part.attribute_at(p, i) {
          Ok(#(word, good)) ->
            card_view.noted(
              shown,
              word <> ": " <> card_view.change_text(s, plain, c),
              good,
            )
          Error(Nil) -> shown
        }
      }),
    ),
  ])
}

pub fn plain_card(s: Scale, c: card.Card) -> Element(msg) {
  card_view.view(
    s,
    c,
    current: c.value,
    key: None,
    dim: False,
    on_click: None,
    charge: None,
  )
}

/// The last upgrade: the card before and after, with what changed.
/// The last workshop upgrade (part name, change): the card before and after.
pub fn view_upgrade(
  s: Scale,
  upgraded: Option(#(String, upgrade.Change)),
) -> Element(msg) {
  case upgraded {
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
          card_view.noted(plain_card(s, change.before), "before", False),
          card_view.noted(
            plain_card(s, change.after),
            "after: " <> card_view.change_text(s, change.before, change.after),
            True,
          ),
        ]),
      ])
  }
}
