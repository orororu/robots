//// The start menu's messages, pure: the root saves and opens what's chosen.

import gleam/option.{None, Some}
import robots/meta/profile.{type Profile}
import robots/run/state.{type Run}
import robots_client/menu/model.{type Menu, type Msg, ContinueRun, NewGame}

pub type Outcome {
  Nothing
  /// Continue this run.
  Continued(run: Run)
  /// To the hangar, with the profile after paying out an abandoned run.
  ToHangar(profile: Profile)
}

pub fn update(menu: Menu, p: Profile, msg: Msg) -> Outcome {
  case msg, menu.saved {
    ContinueRun, Some(run) -> Continued(run)
    ContinueRun, None -> Nothing
    // A saved run is abandoned: paid out like a lost one.
    NewGame, Some(run) -> ToHangar(profile.finish(p, run))
    NewGame, None -> ToHangar(p)
  }
}
