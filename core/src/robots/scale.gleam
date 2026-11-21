//// Display scale: turns relative amounts into the numbers players see.
//// With cost scale 10, a card costing 1.2 shows as 12. Changing the scale
//// changes nothing about balance.
////
//// Energy is shown on the cost scale; HP and card values on the value scale.

import gleam/float

pub type Scale {
  Scale(cost: Float, value: Float)
}

pub fn default() -> Scale {
  Scale(cost: 10.0, value: 10.0)
}

pub fn cost(scale: Scale, amount: Float) -> Int {
  float.round(amount *. scale.cost)
}

pub fn value(scale: Scale, amount: Float) -> Int {
  float.round(amount *. scale.value)
}

/// Rounded *down*, so a bar never claims energy you can't spend yet.
pub fn energy(scale: Scale, amount: Float) -> Int {
  float.truncate(amount *. scale.cost +. 0.000001)
}
