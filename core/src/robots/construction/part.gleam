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

/// Give the card at `index` an attribute, replacing any it had. Does
/// nothing if the attribute wouldn't affect that card.
pub fn attach(
  component: Component,
  index: Int,
  attribute: Attribute,
) -> Component {
  case list.drop(component.cards, index) {
    [c, ..] ->
      case attribute.applies_to(attribute, c) {
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
      Ok(a) -> attribute.apply(a, c)
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

/// "Light overclocked laser", "Broken rapid machine gun": part modifiers,
/// then the two most impactful card attributes, then the part.
pub fn display_name(component: Component) -> String {
  let modifiers =
    list.map(component.modifiers, fn(m) {
      case m {
        Light(_) -> "Light"
        Overclocked(_) -> "Overclocked"
      }
    })
  let attributes = list.take(attribute.ranked(attached(component)), 2)
  list.flatten([modifiers, attributes, [component.name]])
  |> string.join(" ")
  |> sentence_case
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
