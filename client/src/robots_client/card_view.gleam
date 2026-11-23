//// A card drawn as a box: name, value, cost, what it does, tags. Its color
//// says its role: red attacks, blue defences, green buffs, grey specials.
//// Used on the battle table and in the garage.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import robots/rules/card.{type Card}
import robots/rules/scale.{type Scale}

pub type Role {
  Attack
  Defence
  Buff
  Special
}

/// What a card does, from its target (tags are descriptive only).
pub fn role(c: Card) -> Role {
  case c.target {
    card.OpponentHp | card.Launch(_) -> Attack
    card.Opponent(_) | card.Both(_) -> Defence
    card.Self(_) -> Buff
    card.Burn(_) | card.NoEffect -> Special
  }
}

fn role_class(role: Role) -> String {
  case role {
    Attack -> "attack"
    Defence -> "defence"
    Buff -> "buff"
    Special -> "special"
  }
}

fn role_name(role: Role) -> String {
  case role {
    Attack -> "ATTACK"
    Defence -> "DEFENCE"
    Buff -> "BUFF"
    Special -> "SPECIAL"
  }
}

/// A card. `current` is its value now (on the table it may be raised or
/// lowered; elsewhere pass `c.value`). `key` labels it ("1" for the key
/// that plays it); `dim` greys it out (can't afford it); `on_click` makes
/// it a button.
pub fn view(
  s: Scale,
  c: Card,
  current current: Float,
  key key: Option(String),
  dim dim: Bool,
  on_click on_click: Option(msg),
) -> Element(msg) {
  let role = role(c)
  let shown = scale.value(s, current)
  let printed = scale.value(s, c.value)
  let value = case shown == printed {
    True -> int.to_string(shown)
    False -> int.to_string(shown) <> " (" <> int.to_string(printed) <> ")"
  }
  let value_line = case c.target {
    card.Launch(drone) -> "launches a " <> string.lowercase(drone.name)
    card.Burn(_) -> "burns a card at 0"
    card.NoEffect -> "does nothing"
    _ -> value
  }
  let classes =
    "cardbox "
    <> role_class(role)
    <> case dim {
      True -> " dim"
      False -> ""
    }
    <> case on_click {
      Some(_) -> " clickable"
      None -> ""
    }
  let events = case on_click {
    Some(msg) -> [event.on_click(msg)]
    None -> []
  }
  let extras =
    list.flatten([
      case card.has_trait(c, card.Once) {
        True -> ["once"]
        False -> []
      },
      case card.growth(c) {
        Ok(#(_, cap)) -> ["grows to " <> int.to_string(scale.value(s, cap))]
        Error(Nil) -> []
      },
    ])
  html.div([attribute.class(classes), ..events], [
    html.div([attribute.class("cardhead")], [
      html.span([attribute.class("cardrole")], [
        element.text(case key {
          Some(k) -> "[" <> k <> "] " <> role_name(role)
          None -> role_name(role)
        }),
      ]),
      html.span([attribute.class("cardcost")], [
        element.text("⚡" <> int.to_string(scale.cost(s, c.cost))),
      ]),
    ]),
    html.div([attribute.class("cardname")], [element.text(c.name)]),
    html.div([attribute.class("cardvalue")], [element.text(value_line)]),
    html.div([attribute.class("cardtarget")], [element.text(target_text(c))]),
    html.div([attribute.class("cardtags")], [
      element.text(
        string.join(detail_tags(c), " · ")
        <> case extras {
          [] -> ""
          _ -> "\n" <> string.join(extras, " · ")
        },
      ),
    ]),
  ])
}

/// A row of cards that wraps.
pub fn row(cards: List(Element(msg))) -> Element(msg) {
  html.div([attribute.class("cards")], cards)
}

/// "hits the foe", "lowers one foe attack (melee)", ...
pub fn target_text(c: Card) -> String {
  case c.target {
    card.OpponentHp -> "hits the foe"
    card.Opponent(scope) -> "lowers " <> scope_text(scope, "foe")
    card.Self(scope) -> "raises " <> scope_text(scope, "own")
    card.Both(scope) -> "lowers " <> scope_text(scope, "every")
    card.Burn(_) -> "foe card at 0 burns"
    card.NoEffect -> "clears when played"
    card.Launch(_) -> "it strikes later"
  }
}

/// "one foe melee attack", "all own attacks", "one foe drone".
fn scope_text(scope: card.Scope, whose: String) -> String {
  let #(all, tags) = case scope {
    card.One(tags) -> #(False, tags)
    card.All(tags) -> #(True, tags)
  }
  let noun = case list.contains(tags, card.Attack), tags {
    True, _ -> "attack"
    False, [card.Drone] -> "drone"
    False, _ -> "card"
  }
  let qualifiers =
    tags
    |> list.filter(fn(t) {
      t != card.Attack && !{ noun == "drone" && t == card.Drone }
    })
    |> list.map(card.tag_name)
  let count = case all {
    True -> "all "
    False -> "one "
  }
  let plural = case all {
    True -> "s"
    False -> ""
  }
  count <> string.join([whose, ..qualifiers], " ") <> " " <> noun <> plural
}

/// Tags other than the role ones (the color shows the role).
fn detail_tags(c: Card) -> List(String) {
  c.tags
  |> list.filter(fn(t) {
    t != card.Attack && t != card.Defence && t != card.Buff
  })
  |> list.map(card.tag_name)
}
