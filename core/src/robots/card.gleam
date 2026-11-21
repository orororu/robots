import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub type Effect {
  /// Hit the opposing robot. Shield absorbs damage first.
  Damage(amount: Int)
  /// Add shield to your own robot.
  Shield(amount: Int)
  /// Restore your robot's HP (up to its maximum).
  Repair(amount: Int)
  /// Instantly gain energy.
  Charge(amount: Float)
}

pub type Card {
  Card(name: String, cost: Int, effects: List(Effect))
}

pub fn describe(card: Card) -> String {
  card.effects
  |> list.map(describe_effect)
  |> string.join(", ")
}

fn describe_effect(effect: Effect) -> String {
  case effect {
    Damage(n) -> "deal " <> int.to_string(n)
    Shield(n) -> "shield " <> int.to_string(n)
    Repair(n) -> "repair " <> int.to_string(n)
    Charge(x) -> "+" <> float.to_string(x) <> " energy"
  }
}
