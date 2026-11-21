//// Cards. Costs and values are *relative*: 1.0 is the base amount. How big
//// they look to players is decided by `robots/scale`, never here.

import gleam/list
import gleam/string

pub type Tag {
  // Main tags: decide what a card does when played.
  Attack
  Defence
  Buff
  // Descriptive tags: decide what a defence or buff can target.
  Melee
  Range
  Beam
  Energy
  Kinetic
  Mobility
}

/// Which table cards a defence (opponent's table) or buff (own table) affects.
/// A target must have *all* the listed tags.
pub type Reach {
  /// Attack cards don't touch the table; they hit the opponent's HP.
  NoReach
  /// One random matching card.
  One(matching: List(Tag))
  /// Every matching card (multi-target cards should have a lower value).
  All(matching: List(Tag))
}

pub type Card {
  Card(name: String, tags: List(Tag), cost: Float, value: Float, reach: Reach)
}

pub type Kind {
  AttackCard
  DefenceCard
  BuffCard
  /// A card with no main tag does nothing when played.
  Inert
}

pub fn kind(card: Card) -> Kind {
  case has(card, Attack), has(card, Defence), has(card, Buff) {
    True, _, _ -> AttackCard
    False, True, _ -> DefenceCard
    False, False, True -> BuffCard
    False, False, False -> Inert
  }
}

pub fn has(card: Card, tag: Tag) -> Bool {
  list.contains(card.tags, tag)
}

pub fn matches(card: Card, required: List(Tag)) -> Bool {
  list.all(required, has(card, _))
}

pub fn tag_name(tag: Tag) -> String {
  case tag {
    Attack -> "attack"
    Defence -> "defence"
    Buff -> "buff"
    Melee -> "melee"
    Range -> "range"
    Beam -> "beam"
    Energy -> "energy"
    Kinetic -> "kinetic"
    Mobility -> "mobility"
  }
}

pub fn tags_text(tags: List(Tag)) -> String {
  "[" <> tags |> list.map(tag_name) |> string.join(",") <> "]"
}
