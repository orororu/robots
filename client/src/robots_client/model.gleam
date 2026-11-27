//// The client's state and messages. Each feature keeps its own part
//// (`menu/model`, `hangar/model`, `map/model`, `garage/model`,
//// `battle/model`); the root holds them and what's shared: the profile, the
//// run, the clock and the banner.

import gleam/option.{type Option, None}
import robots/meta/profile.{type Profile}
import robots/rules/scale.{type Scale}
import robots/run/state.{type Run}
import robots_client/battle/model.{type Combat} as battle_model
import robots_client/garage/model.{type Garage} as garage_model
import robots_client/hangar/model.{type Hangar} as hangar_model
import robots_client/map/model.{type Journal} as map_model
import robots_client/menu/model.{type Menu} as menu_model

pub const frame_ms = 50

pub const flash_ms = 2500

pub type Model {
  Model(
    /// What carries over between runs; saved in the browser.
    profile: Profile,
    /// Between runs: the hangar, where Data is spent and the starting
    /// robots designed. `run` is the last run (or a placeholder) meanwhile.
    hangar: Option(Hangar),
    /// The start menu, while it's open.
    menu: Option(Menu),
    run: Run,
    journal: Journal,
    garage: Garage,
    combat: Combat,
    scale: Scale,
    now: Int,
    flash: String,
    flash_until: Int,
  )
}

pub type Msg {
  Frame(now: Int)
  KeyDown(key: String)
  MenuMsg(menu_model.Msg)
  MapMsg(map_model.Msg)
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
    menu: None,
    run:,
    journal: map_model.new_journal("A new run. Pick where to go."),
    garage: garage_model.new_garage(),
    combat: battle_model.new_combat(run),
    scale: scale.default(),
    now:,
    flash: "",
    flash_until: 0,
  )
}
