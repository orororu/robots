//// Helpers both update modules share: try a run change, flash a
//// message, save the run, open the hangar.

import gleam/option.{None, Some}

import robots/meta/profile.{type Profile}

import robots/run/save
import robots/run/state.{type Run}
import robots_client/browser

import robots_client/model.{
  type Model, Model, default_order, flash_ms, hangar_for, no_pick,
}
import robots_client/wording.{describe_error}

/// Save the profile and go to the hangar.
pub fn open_hangar(model: Model, p: Profile) -> Model {
  browser.save_profile(profile.encode(p))
  // The run is over and paid out: nothing to continue.
  browser.save_run("")
  Model(
    ..model,
    profile: p,
    hangar: Some(hangar_for(p)),
    battle: None,
    report: None,
  )
}

/// Apply a run step; on success clear the garage selection and reset the
/// battle order (robots may have come or gone).
pub fn attempt(
  model: Model,
  result: Result(Run, state.Error),
  news: String,
) -> Model {
  case result {
    Ok(run) -> {
      keep(run)
      Model(
        ..model,
        run:,
        pick: no_pick,
        order: default_order(run),
        news: case news {
          "" -> model.news
          _ -> news
        },
      )
    }
    Error(error) -> flash(model, describe_error(error))
  }
}

pub fn flash(model: Model, text: String) -> Model {
  Model(..model, flash: text, flash_until: model.now + flash_ms)
}

/// Save the run, so a reload continues it.
pub fn keep(run: Run) -> Nil {
  browser.save_run(save.encode(run))
}
