//// Cards. Costs and values are *relative*: 1.0 is the base amount. How big
//// they look to players is decided by `robots/scale`, never here.
////
//// What a card does is decided by its `target` alone: targeting the opponent
//// lowers (damage, weaken), targeting yourself raises (repair, buff), always
//// by the card's current value. Tags only describe cards, so that scopes like
//// `One([Attack, Melee])` can select them.

import gleam/list
import gleam/string

pub type Tag {
  Attack
  Defence
  Buff
  Melee
  Range
  Beam
  Energy
  Kinetic
  Mobility
}

/// Whose side a card affects. `Opponent` lowers, `Self` raises.
pub type Target {
  Opponent(scope: Scope)
  Self(scope: Scope)
}

/// What on that side is affected.
pub type Scope {
  /// The robot's HP (damage for `Opponent`, repair up to max HP for `Self`).
  Hp
  /// One random table card having all these tags.
  One(matching: List(Tag))
  /// Every table card having all these tags. Should have a lower value.
  All(matching: List(Tag))
}

pub type Card {
  Card(name: String, tags: List(Tag), cost: Float, value: Float, target: Target)
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
