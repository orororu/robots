//// Arithmetic for relative amounts (HP, card values).
////
//// Floats drift: 1.0 - 0.7 - 0.3 is 5.5e-17, not 0. Anything this small is
//// treated as exactly zero, so a robot "at 0 HP" really is destroyed and a
//// card "at value 0" really does nothing.

import gleam/float

const epsilon = 0.000001

/// `a - b`, never below zero.
pub fn subtract(a: Float, b: Float) -> Float {
  let result = a -. b
  case result <. epsilon {
    True -> 0.0
    False -> result
  }
}

/// `a >= b`, forgiving float drift (energy 1.1999999 can pay a cost of 1.2).
pub fn at_least(a: Float, b: Float) -> Bool {
  a +. epsilon >=. b
}

pub fn is_zero(a: Float) -> Bool {
  float.absolute_value(a) <. epsilon
}
