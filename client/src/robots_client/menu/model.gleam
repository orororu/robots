//// The start menu: the run saved in the browser, which it can continue.

import gleam/option.{type Option}
import robots/run/state.{type Run}

pub type Menu {
  Menu(saved: Option(Run))
}

pub type Msg {
  /// Continue the saved run.
  ContinueRun
  /// Start a new run in the hangar; a saved run is abandoned.
  NewGame
}
