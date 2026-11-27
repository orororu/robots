//// The client's state and messages. Each feature keeps its own part
//// (`hangar_model`, `garage_model`, `battle_model`); the root holds them
//// and what's shared: the profile, the run, the clock and messages.

import gleam/option.{type Option, None}
import robots/meta/profile.{type Profile}
import robots/rules/scale.{type Scale}
import robots/run/state.{type Run}
import robots_client/battle_model.{type Combat}
import robots_client/garage_model.{type Garage}
import robots_client/hangar_model.{type Hangar}

pub const frame_ms = 50

pub const flash_ms = 2500

pub type Model {
  Model(
    /// What carries over between runs; saved in the browser.
    profile: Profile,
    /// Between runs: the hangar, where Data is spent and the starting
    /// robots designed. `run` is the last run (or a placeholder) meanwhile.
    hangar: Option(Hangar),
    /// The start menu: continue the saved run, or a new one.
    menu: Bool,
    /// The run saved in the browser, while the menu can continue it.
    saved: Option(Run),
    run: Run,
    garage: Garage,
    combat: Combat,
    /// What the last step did (a battle's pay, an upgrade), shown on the
    /// map.
    news: String,
    scale: Scale,
    now: Int,
    flash: String,
    flash_until: Int,
  )
}

pub type Msg {
  Frame(now: Int)
  KeyDown(key: String)
  // The start menu
  ContinueRun
  NewGame
  /// After a run: pay it out and go to the hangar.
  ToHangar
  // Map
  Go(node: Int)
  HangarMsg(hangar_model.Msg)
  GarageMsg(garage_model.Msg)
  BattleMsg(battle_model.Msg)
}

/// A model for `run`, in the hangar if `hangar` is given.
pub fn new_model(
  run: Run,
  profile: Profile,
  hangar: Option(Hangar),
  now: Int,
) -> Model {
  Model(
    profile:,
    hangar:,
    menu: False,
    saved: None,
    run:,
    garage: garage_model.new_garage(),
    combat: battle_model.new_combat(run),
    news: "A new run. Pick where to go.",
    scale: scale.default(),
    now:,
    flash: "",
    flash_until: 0,
  )
}
