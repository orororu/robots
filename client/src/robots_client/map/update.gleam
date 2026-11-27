//// The map's messages, pure: the root saves the run and pays it out.

import gleam/option.{None}
import robots/meta/profile.{type Profile}
import robots/run/state.{type Run}
import robots_client/map/model.{type Journal, type Msg, Go, Journal, ToHangar}

pub type Outcome {
  Went(run: Run)
  Failed(state.Error)
  /// The run is over: the profile after paying it out.
  Finished(profile: Profile)
}

pub fn update(
  j: Journal,
  run: Run,
  p: Profile,
  msg: Msg,
) -> #(Journal, Outcome) {
  case msg {
    Go(node) ->
      case state.go(run, node) {
        // The upgrade is shown until the next step.
        Ok(run) -> #(Journal(..j, upgraded: None), Went(run))
        Error(e) -> #(j, Failed(e))
      }
    ToHangar -> #(j, Finished(profile.finish(p, run)))
  }
}
