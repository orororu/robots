//// Cards. Costs and values are *relative*: 1.0 is the base amount. How big
//// they look to players is decided by `robots/scale`, never here.
////
//// What a card does is decided by its `target` alone: damage the opponent's
//// HP, lower the opponent's table cards (weaken), raise your own (buff), or
//// lower both tables (Smoke), always by the card's current value. Tags only describe cards, so that
//// scopes like `One([Attack, Melee])` can select them.
////
//// There is no healing during a match: no target can raise HP. Robots are
//// repaired between matches (`robot.repair`).

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
  Explosive
  /// Drones are not attacks: shields and attack buffs don't affect them.
  Drone
}

/// What a card affects.
pub type Target {
  /// Damage the opponent's robot.
  OpponentHp
  /// Lower cards on the opponent's table.
  Opponent(scope: Scope)
  /// Raise cards on your own table.
  Self(scope: Scope)
  /// Lower cards on both tables, yours too (Smoke blocks everyone's view).
  Both(scope: Scope)
  /// Put this drone card into the played card's table slot.
  Launch(drone: Card)
}

/// Which table cards are affected.
pub type Scope {
  /// One random table card having all these tags.
  One(matching: List(Tag))
  /// Every table card having all these tags. Should have a lower value.
  All(matching: List(Tag))
}

pub type Card {
  Card(
    name: String,
    tags: List(Tag),
    cost: Float,
    value: Float,
    target: Target,
    /// Special rules, usually none.
    traits: List(Trait),
  )
}

/// Special rules a card can have.
pub type Trait {
  /// Played once per match: afterwards the card leaves the game instead of
  /// going to the discard pile. Rated above normal efficiency to make up
  /// for it.
  Once
  /// The card's value grows by `per_second` while it waits on the table, up
  /// to `cap` (drones).
  Grows(per_second: Float, cap: Float)
}

/// A drone's growth, if the card has any.
pub fn growth(card: Card) -> Result(#(Float, Float), Nil) {
  list.find_map(card.traits, fn(t) {
    case t {
      Grows(per_second:, cap:) -> Ok(#(per_second, cap))
      _ -> Error(Nil)
    }
  })
}

pub fn has_trait(card: Card, trait: Trait) -> Bool {
  list.contains(card.traits, trait)
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
    Explosive -> "explosive"
    Drone -> "drone"
  }
}

pub fn tags_text(tags: List(Tag)) -> String {
  "[" <> tags |> list.map(tag_name) |> string.join(",") <> "]"
}
