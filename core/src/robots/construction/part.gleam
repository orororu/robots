//// Components: the parts a robot is built from. See docs/BUILDER.md.
////
//// A part's weight is an attribute of its type (a cannon is heavy, a laser
//// light). Loot quality comes from modifiers on top of a base part: "Light"
//// parts weigh less, "Overclocked" parts are stronger.

import gleam/float
import gleam/list
import gleam/string
import robots/construction/attribute.{type Attribute}
import robots/rules/card.{type Card, Card}

pub type Kind {
  /// The chassis' own cards (mobility and the like). Comes with the chassis;
  /// not bought or installed separately.
  Body
  Weapon
  Defence
  Armor
  Battery
  Utility
}

pub type Modifier {
  /// Weight multiplier, e.g. 0.75 = 25% lighter. Same cards.
  Light(weight: Float)
  /// Multiplier for what the part provides (card values, armor HP, battery
  /// capacity), e.g. 1.15 = +15%. Card costs and weight stay the same.
  Overclocked(value: Float)
}

pub type Component {
  Component(
    name: String,
    kind: Kind,
    weight: Float,
    cards: List(Card),
    /// Extra HP (armor). Relative, like card values.
    hp: Float,
    /// Energy storage (battery). Relative, like card costs.
    energy_cap: Float,
    modifiers: List(Modifier),
    /// Damage this part has taken and kept (armor, during a run). Its
    /// remaining HP is `hp - wear`. See `robots/construction/wear`.
    wear: Float,
    /// Card attributes from loot: `#(card index, attribute)`, at most one
    /// per card. See `robots/construction/attribute`.
    attributes: List(#(Int, Attribute)),
  )
}

/// Standard loot modifiers.
pub fn light() -> Modifier {
  Light(weight: 0.75)
}

pub fn overclocked() -> Modifier {
  Overclocked(value: 1.15)
}

/// A part that only adds cards.
pub fn new(
  name: String,
  kind: Kind,
  weight: Float,
  cards: List(Card),
) -> Component {
  Component(
    name:,
    kind:,
    weight:,
    cards:,
    hp: 0.0,
    energy_cap: 0.0,
    modifiers: [],
    wear: 0.0,
    attributes: [],
  )
}

pub fn armor(
  name: String,
  weight: Float,
  hp: Float,
  cards: List(Card),
) -> Component {
  Component(..new(name, Armor, weight, cards), hp:)
}

pub fn battery(
  name: String,
  weight: Float,
  energy_cap: Float,
  cards: List(Card),
) -> Component {
  Component(..new(name, Battery, weight, cards), energy_cap:)
}

pub fn with(component: Component, modifier: Modifier) -> Component {
  Component(
    ..component,
    modifiers: list.append(component.modifiers, [modifier]),
  )
}

// EFFECTIVE STATS (modifiers applied) -----------------------------------------

pub fn weight(component: Component) -> Float {
  list.fold(component.modifiers, component.weight, fn(w, m) {
    case m {
      Light(factor) -> w *. factor
      Overclocked(_) -> w
    }
  })
}

/// What an attribute is called on this kind of part: "Precise" makes sense
/// for a gun, not for a plate. Armor speaks of its condition and toughness
/// ("Dented", "Thick"); attributes with no word for a kind never go on it.
pub fn attribute_word(kind: Kind, a: Attribute) -> Result(String, Nil) {
  case kind {
    Armor ->
      list.key_find(
        [
          #(attribute.broken(), "Broken"),
          #(attribute.damaged(), "Dented"),
          #(attribute.weak(), "Thin"),
          #(attribute.worn(), "Scratched"),
          #(attribute.crude(), "Crude"),
          #(attribute.tuned(), "Hardened"),
          #(attribute.strong(), "Thick"),
          #(attribute.masterwork(), "Masterwork"),
        ],
        a,
      )
    _ -> Ok(a.name)
  }
}

/// Whether the card at `index` can take the attribute: it must change the
/// card, and make sense on this kind of part.
pub fn can_attach(component: Component, index: Int, a: Attribute) -> Bool {
  case list.drop(component.cards, index), attribute_word(component.kind, a) {
    [c, ..], Ok(_) -> attribute.applies_to(a, c)
    _, _ -> False
  }
}

/// Give the card at `index` an attribute, replacing any it had. Does
/// nothing if it can't take it (`can_attach`).
pub fn attach(
  component: Component,
  index: Int,
  attribute: Attribute,
) -> Component {
  case list.drop(component.cards, index) {
    [_, ..] ->
      case can_attach(component, index, attribute) {
        True ->
          Component(..component, attributes: [
            #(index, attribute),
            ..list.filter(component.attributes, fn(pair) { pair.0 != index })
          ])
        False -> component
      }
    [] -> component
  }
}

/// The part's cards with attributes and modifiers applied.
pub fn cards(component: Component) -> List(Card) {
  let boost = strength(component)
  list.index_map(component.cards, fn(c, i) {
    let c = case list.key_find(component.attributes, i) {
      Ok(a) ->
        Card(..attribute.apply(a, c), name: word(component, a) <> " " <> c.name)
      Error(Nil) -> c
    }
    Card(..c, value: c.value *. boost)
  })
}

/// Each attribute with the card it's on (before attributes).
pub fn attached(component: Component) -> List(#(Attribute, Card)) {
  list.filter_map(component.attributes, fn(pair) {
    case list.drop(component.cards, pair.0) {
      [c, ..] -> Ok(#(pair.1, c))
      [] -> Error(Nil)
    }
  })
}

/// Full HP, when undamaged.
pub fn hp(component: Component) -> Float {
  component.hp *. strength(component)
}

/// HP left after wear.
pub fn remaining_hp(component: Component) -> Float {
  float.max(0.0, hp(component) -. component.wear)
}

pub fn energy_cap(component: Component) -> Float {
  component.energy_cap *. strength(component)
}

/// How much the part's modifiers multiply what it provides (1.0 = none).
pub fn strength(component: Component) -> Float {
  list.fold(component.modifiers, 1.0, fn(s, m) {
    case m {
      Overclocked(factor) -> s *. factor
      Light(_) -> s
    }
  })
}

/// "Light overclocked laser", "Broken rapid machine gun", "Reinforced
/// thick plating": part modifiers, then the two most impactful card
/// attributes, then the part.
pub fn display_name(component: Component) -> String {
  let modifiers =
    list.map(component.modifiers, modifier_word(component.kind, _))
  let attributes =
    attribute.ranked(attached(component))
    |> list.take(2)
    |> list.map(fn(name) {
      case
        list.find(component.attributes, fn(pair) { { pair.1 }.name == name })
      {
        Ok(#(_, a)) -> word(component, a)
        Error(Nil) -> name
      }
    })
  list.flatten([modifiers, attributes, [component.name]])
  |> string.join(" ")
  |> sentence_case
}

/// What a modifier is called on this kind of part: an Overclocked plate is
/// "Reinforced", an Overclocked battery "High-capacity".
pub fn modifier_word(kind: Kind, modifier: Modifier) -> String {
  case modifier, kind {
    Light(_), _ -> "Light"
    Overclocked(_), Armor -> "Reinforced"
    Overclocked(_), Battery -> "High-capacity"
    Overclocked(_), _ -> "Overclocked"
  }
}

fn word(component: Component, a: Attribute) -> String {
  case attribute_word(component.kind, a) {
    Ok(w) -> w
    Error(Nil) -> a.name
  }
}

fn sentence_case(text: String) -> String {
  case string.pop_grapheme(text) {
    Ok(#(first, rest)) -> first <> string.lowercase(rest)
    Error(Nil) -> text
  }
}

pub fn kind_name(kind: Kind) -> String {
  case kind {
    Body -> "chassis"
    Weapon -> "weapon"
    Defence -> "defence"
    Armor -> "armor"
    Battery -> "battery"
    Utility -> "utility"
  }
}

/// Total weight of several parts.
pub fn total_weight(parts: List(Component)) -> Float {
  parts |> list.map(weight) |> float.sum
}
