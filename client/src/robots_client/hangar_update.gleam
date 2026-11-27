//// The hangar's messages, by what they change:
////
//// - `select`: only the hangar (what's selected, which tab is open);
//// - `edit`: the designs, reading the profile for the fabricator's spares;
//// - `spend`: the profile too (research, selling);
//// - `start`: a run from the designs.
////
//// They're pure; `update` saves the profile, flashes messages and rolls the
//// run's seed.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import robots/construction/builder
import robots/construction/part
import robots/meta/blueprint.{
  type Blueprint, ChassisBlueprint, FabricatorBlueprint, PartBlueprint,
}
import robots/meta/profile.{type Profile}
import robots/run/state.{type Run}
import robots_client/actions.{flash, keep}
import robots_client/browser
import robots_client/model.{
  type Hangar, type Model, type Msg, AddPart, AssembleDesign, Hangar, HangarGo,
  HangarInstalled, HangarOwnChassis, HangarSelect, HangarSpare,
  HangarSpareChassis, Model, NewRoom, NoHangarPick, PickDesignChassis, PickDraft,
  PickFound, PickGarage, PickSpareChassis, RemovePart, Research, Room,
  SellBlueprint, StartRun, SwapPart, UseChassis, at, new_model, room, set_room,
  spare_chassis, spare_parts, tidy, toggle,
}
import robots_client/wording.{describe_profile_error}

/// Apply a hangar message to the model: the pure steps below, then saving
/// and messages.
pub fn update(model: Model, msg: Msg) -> Model {
  case model.hangar {
    None -> model
    Some(h) ->
      case msg {
        StartRun ->
          case start(model.profile, h, browser.random_seed()) {
            Ok(#(p, run)) -> {
              browser.save_profile(profile.encode(p))
              keep(run)
              new_model(run, p, None, model.now)
            }
            Error(e) -> flash(model, describe_profile_error(e))
          }
        Research | SellBlueprint ->
          case spend(model.profile, h, msg) {
            Ok(#(p, h, message)) -> {
              browser.save_profile(profile.encode(p))
              flash(
                Model(..model, profile: p, hangar: Some(h), news: message),
                message,
              )
            }
            Error(e) -> flash(model, describe_profile_error(e))
          }
        AddPart | RemovePart | SwapPart | UseChassis | AssembleDesign ->
          case edit(model.profile, h, msg) {
            Ok(#(h, "")) -> Model(..model, hangar: Some(h))
            Ok(#(h, message)) -> flash(Model(..model, hangar: Some(h)), message)
            Error(reason) -> flash(model, reason)
          }
        _ -> Model(..model, hangar: Some(select(h, msg)))
      }
  }
}

/// Selecting and switching tabs.
pub fn select(h: Hangar, msg: Msg) -> Hangar {
  let toggle_pick = fn(pick) {
    case h.pick == pick {
      True -> NoHangarPick
      False -> pick
    }
  }
  case msg {
    HangarSelect(pick) -> Hangar(..h, pick: toggle_pick(pick))
    HangarGo(screen) -> Hangar(..h, screen:, pick: NoHangarPick)
    HangarOwnChassis -> Hangar(..h, pick: toggle_pick(PickDesignChassis))
    HangarInstalled(i) -> {
      let pick = case h.pick {
        PickGarage(installed, spare) -> PickGarage(toggle(installed, i), spare)
        _ -> PickGarage(Some(i), None)
      }
      Hangar(..h, pick: tidy(pick))
    }
    HangarSpare(i) -> {
      let pick = case h.pick {
        PickDraft(c, parts) ->
          PickDraft(c, case list.contains(parts, i) {
            True -> list.filter(parts, fn(x) { x != i })
            False -> list.append(parts, [i])
          })
        PickGarage(installed, spare) -> PickGarage(installed, toggle(spare, i))
        _ -> PickGarage(None, Some(i))
      }
      Hangar(..h, pick: tidy(pick))
    }
    HangarSpareChassis(i) ->
      Hangar(..h, pick: case h.screen, h.pick {
        NewRoom, PickDraft(c, _) if c == i -> NoHangarPick
        NewRoom, _ -> PickDraft(i, [])
        _, PickSpareChassis(c) if c == i -> NoHangarPick
        _, _ -> PickSpareChassis(i)
      })
    _ -> h
  }
}

/// Changes to the designs, from the fabricator's spares. `Ok` carries a
/// message to show ("" for none); `Error` why it can't be done.
pub fn edit(
  p: Profile,
  h: Hangar,
  msg: Msg,
) -> Result(#(Hangar, String), String) {
  let d = room(h)
  let spares = spare_parts(p, h.designs)
  let quiet = fn(h) { Ok(#(h, "")) }
  case msg, h.pick {
    AddPart, PickGarage(None, Some(j)) ->
      case at(spares, j) {
        Some(c) ->
          quiet(set_room(
            h,
            profile.Design(..d, parts: list.append(d.parts, [c])),
          ))
        None -> quiet(h)
      }
    RemovePart, PickGarage(Some(i), None) ->
      quiet(set_room(h, profile.Design(..d, parts: without(d.parts, i))))
    SwapPart, PickGarage(Some(i), Some(j)) ->
      case at(spares, j) {
        Some(c) ->
          quiet(set_room(h, profile.Design(..d, parts: replace(d.parts, i, c))))
        None -> quiet(h)
      }
    // Rebuild the design on a spare chassis: the parts that fit stay, the
    // rest go back to the fabricator's spares.
    UseChassis, PickSpareChassis(i) ->
      case chassis_at(p, h, i) {
        Some(c) -> {
          let #(kept, dropped) = builder.fit(c, d.parts)
          use _ <- result.try(
            builder.build(d.name, c, kept)
            |> result.map_error(fn(errors) {
              string.join(list.map(errors, builder.describe_error), "; ")
            }),
          )
          Ok(#(
            set_room(h, profile.Design(..d, chassis: c.name, parts: kept)),
            "Rebuilt "
              <> d.name
              <> " on the "
              <> c.name
              <> "."
              <> case dropped {
              [] -> ""
              _ ->
                " Back to the spares: "
                <> string.join(list.map(dropped, part.display_name), ", ")
                <> "."
            },
          ))
        }
        None -> quiet(h)
      }
    AssembleDesign, PickDraft(c, parts) ->
      case at(spare_chassis(p, h.designs), c) {
        Some(chassis) -> {
          let new =
            profile.Design(
              name: "Robot " <> int.to_string(list.length(h.designs) + 1),
              chassis:,
              parts: list.filter_map(parts, fn(j) {
                at(spares, j) |> option.to_result(Nil)
              }),
            )
          use _ <- result.try(
            profile.fabricate(p, new)
            |> result.map_error(describe_profile_error),
          )
          quiet(Hangar(
            designs: list.append(h.designs, [new]),
            pick: NoHangarPick,
            screen: Room(list.length(h.designs)),
          ))
        }
        None -> quiet(h)
      }
    _, _ -> quiet(h)
  }
}

/// Research a found blueprint, or sell the selected one. Returns the new
/// profile, the hangar and what to tell the player.
pub fn spend(
  p: Profile,
  h: Hangar,
  msg: Msg,
) -> Result(#(Profile, Hangar, String), profile.Error) {
  case msg, h.pick {
    Research, PickFound(b) -> {
      use p <- result.map(profile.research(p, b))
      let message = case b {
        FabricatorBlueprint ->
          "The fabricator now builds "
          <> int.to_string(p.fabricator)
          <> " robots a run: design the next one in the + New robot tab."
        _ ->
          "Researched " <> blueprint.describe(b) <> ": it's in the fabricator."
      }
      #(p, Hangar(..h, pick: NoHangarPick), message)
    }
    SellBlueprint, PickFound(b) -> sold(h, b, profile.sell_found(p, b))
    SellBlueprint, PickGarage(None, Some(j)) ->
      case at(spare_parts(p, h.designs), j) {
        Some(c) -> {
          let b = PartBlueprint(c)
          sold(h, b, profile.sell_researched(p, b))
        }
        None -> Ok(#(p, h, ""))
      }
    SellBlueprint, PickSpareChassis(i) ->
      case at(spare_chassis(p, h.designs), i) {
        Some(name) -> {
          let b = ChassisBlueprint(name)
          sold(h, b, profile.sell_researched(p, b))
        }
        None -> Ok(#(p, h, ""))
      }
    _, _ -> Ok(#(p, h, ""))
  }
}

/// After a sale: a found blueprint stays selected while copies are left;
/// a spare's indexes shift, so its selection is cleared.
fn sold(
  h: Hangar,
  b: Blueprint,
  result: Result(Profile, profile.Error),
) -> Result(#(Profile, Hangar, String), profile.Error) {
  use p <- result.map(result)
  let left = case h.pick {
    PickFound(_) -> list.contains(p.found, b)
    _ -> False
  }
  let pick = case left {
    True -> h.pick
    False -> NoHangarPick
  }
  #(p, Hangar(..h, pick:), "Sold " <> blueprint.describe(b) <> ".")
}

/// Save the designs into the profile and start a run with the fabricated
/// robots.
pub fn start(
  p: Profile,
  h: Hangar,
  seed: Int,
) -> Result(#(Profile, Run), profile.Error) {
  use p <- result.try(
    list.index_fold(h.designs, Ok(p), fn(acc, d, i) {
      result.try(acc, profile.set_design(_, i, d))
    }),
  )
  use run <- result.map(profile.start(p, seed))
  #(p, run)
}

fn chassis_at(p: Profile, h: Hangar, i: Int) -> Option(builder.Chassis) {
  option.then(at(spare_chassis(p, h.designs), i), fn(name) {
    option.from_result(blueprint.chassis(name))
  })
}

fn without(items: List(a), i: Int) -> List(a) {
  list.append(list.take(items, i), list.drop(items, i + 1))
}

fn replace(items: List(a), i: Int, item: a) -> List(a) {
  list.flatten([list.take(items, i), [item], list.drop(items, i + 1)])
}
