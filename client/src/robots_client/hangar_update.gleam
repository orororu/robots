//// The hangar's messages: research and sell blueprints, edit the
//// designs, start a run.

import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

import robots/construction/builder
import robots/construction/part

import robots/meta/blueprint.{
  type Blueprint, ChassisBlueprint, FabricatorBlueprint, PartBlueprint,
}
import robots/meta/profile.{type Profile}

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

/// Save the profile and go to the hangar.
import robots_client/actions.{flash, keep}

/// The hangar's messages: research, designs, selling, starting a run.
pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    HangarSelect(pick) ->
      update_hangar(model, fn(h) {
        Hangar(..h, pick: case h.pick == pick {
          True -> NoHangarPick
          False -> pick
        })
      })
    Research ->
      case model.hangar {
        Some(Hangar(pick: PickFound(b), ..) as h) ->
          case profile.research(model.profile, b) {
            Ok(p) -> {
              browser.save_profile(profile.encode(p))
              let message = case b {
                FabricatorBlueprint ->
                  "The fabricator now builds "
                  <> int.to_string(p.fabricator)
                  <> " robots a run: design the next one in the + New robot tab."
                _ ->
                  "Researched "
                  <> blueprint.describe(b)
                  <> ": it's in the fabricator."
              }
              flash(
                Model(
                  ..model,
                  profile: p,
                  hangar: Some(Hangar(..h, pick: NoHangarPick)),
                  news: message,
                ),
                message,
              )
            }
            Error(e) -> flash(model, describe_profile_error(e))
          }
        _ -> model
      }
    HangarInstalled(i) ->
      update_hangar(model, fn(h) {
        let pick = case h.pick {
          PickGarage(installed, spare) ->
            PickGarage(toggle(installed, i), spare)
          _ -> PickGarage(Some(i), None)
        }
        Hangar(..h, pick: tidy(pick))
      })
    HangarSpare(i) ->
      update_hangar(model, fn(h) {
        let pick = case h.pick {
          PickDraft(c, parts) ->
            PickDraft(c, case list.contains(parts, i) {
              True -> list.filter(parts, fn(x) { x != i })
              False -> list.append(parts, [i])
            })
          PickGarage(installed, spare) ->
            PickGarage(installed, toggle(spare, i))
          _ -> PickGarage(None, Some(i))
        }
        Hangar(..h, pick: tidy(pick))
      })
    HangarSpareChassis(i) ->
      update_hangar(model, fn(h) {
        Hangar(..h, pick: case h.screen, h.pick {
          NewRoom, PickDraft(c, _) if c == i -> NoHangarPick
          NewRoom, _ -> PickDraft(i, [])
          _, PickSpareChassis(c) if c == i -> NoHangarPick
          _, _ -> PickSpareChassis(i)
        })
      })
    HangarOwnChassis ->
      update_hangar(model, fn(h) {
        Hangar(..h, pick: case h.pick == PickDesignChassis {
          True -> NoHangarPick
          False -> PickDesignChassis
        })
      })
    AddPart ->
      update_hangar(model, fn(h) {
        let d = room(h)
        case h.pick {
          PickGarage(None, Some(j)) ->
            case at(spare_parts(model.profile, h.designs), j) {
              Some(p) ->
                set_room(
                  h,
                  profile.Design(..d, parts: list.append(d.parts, [p])),
                )
              None -> h
            }
          _ -> h
        }
      })
    RemovePart ->
      update_hangar(model, fn(h) {
        let d = room(h)
        case h.pick {
          PickGarage(Some(i), None) ->
            set_room(
              h,
              profile.Design(
                ..d,
                parts: list.append(
                  list.take(d.parts, i),
                  list.drop(d.parts, i + 1),
                ),
              ),
            )
          _ -> h
        }
      })
    SwapPart ->
      update_hangar(model, fn(h) {
        let d = room(h)
        case h.pick {
          PickGarage(Some(i), Some(j)) ->
            case at(spare_parts(model.profile, h.designs), j) {
              Some(p) ->
                set_room(
                  h,
                  profile.Design(
                    ..d,
                    parts: list.flatten([
                      list.take(d.parts, i),
                      [p],
                      list.drop(d.parts, i + 1),
                    ]),
                  ),
                )
              None -> h
            }
          _ -> h
        }
      })
    // Rebuild the design on a spare chassis: the parts that fit stay, the
    // rest go back to the fabricator's spares.
    UseChassis ->
      case model.hangar {
        Some(Hangar(pick: PickSpareChassis(i), ..) as h) ->
          case
            option.then(
              at(spare_chassis(model.profile, h.designs), i),
              fn(name) { option.from_result(blueprint.chassis(name)) },
            )
          {
            Some(c) -> {
              let d = room(h)
              let #(kept, dropped) = builder.fit(c, d.parts)
              use <- bool.lazy_guard(
                result.is_error(builder.build(d.name, c, kept)),
                fn() {
                  case builder.build(d.name, c, kept) {
                    Error(errors) ->
                      flash(
                        model,
                        string.join(
                          list.map(errors, builder.describe_error),
                          "; ",
                        ),
                      )
                    Ok(_) -> model
                  }
                },
              )
              let message =
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
                }
              flash(
                Model(
                  ..model,
                  hangar: Some(set_room(
                    h,
                    profile.Design(..d, chassis: c.name, parts: kept),
                  )),
                ),
                message,
              )
            }
            None -> model
          }
        _ -> model
      }
    AssembleDesign ->
      case model.hangar {
        Some(Hangar(pick: PickDraft(c, parts), ..) as h) -> {
          let spares = spare_parts(model.profile, h.designs)
          case at(spare_chassis(model.profile, h.designs), c) {
            Some(chassis) -> {
              let d =
                profile.Design(
                  name: "Robot " <> int.to_string(list.length(h.designs) + 1),
                  chassis:,
                  parts: list.filter_map(parts, fn(j) {
                    at(spares, j) |> option.to_result(Nil)
                  }),
                )
              case profile.fabricate(model.profile, d) {
                Ok(_) ->
                  Model(
                    ..model,
                    hangar: Some(Hangar(
                      designs: list.append(h.designs, [d]),
                      pick: NoHangarPick,
                      screen: Room(list.length(h.designs)),
                    )),
                  )
                Error(e) -> flash(model, describe_profile_error(e))
              }
            }
            None -> model
          }
        }
        _ -> model
      }
    SellBlueprint ->
      case model.hangar {
        Some(Hangar(pick: PickFound(b), ..) as h) ->
          sell_blueprint(model, h, profile.sell_found(model.profile, b), b)
        Some(Hangar(pick: PickGarage(None, Some(j)), ..) as h) ->
          case at(spare_parts(model.profile, h.designs), j) {
            Some(c) -> {
              let b = PartBlueprint(c)
              sell_blueprint(
                model,
                h,
                profile.sell_researched(model.profile, b),
                b,
              )
            }
            None -> model
          }
        Some(Hangar(pick: PickSpareChassis(i), ..) as h) ->
          case at(spare_chassis(model.profile, h.designs), i) {
            Some(name) -> {
              let b = ChassisBlueprint(name)
              sell_blueprint(
                model,
                h,
                profile.sell_researched(model.profile, b),
                b,
              )
            }
            None -> model
          }
        _ -> model
      }
    StartRun -> start_run(model)
    HangarGo(screen) ->
      update_hangar(model, fn(h) { Hangar(..h, screen:, pick: NoHangarPick) })
    _ -> model
  }
}

/// Sell a blueprint and save; keep it selected while copies are left.
pub fn sell_blueprint(
  model: Model,
  h: Hangar,
  result: Result(Profile, profile.Error),
  b: Blueprint,
) -> Model {
  case result {
    Ok(p) -> {
      browser.save_profile(profile.encode(p))
      // Indexes into the spares shift after a sale: clear the selection.
      let left = case h.pick {
        PickFound(_) -> list.contains(p.found, b)
        _ -> False
      }
      Model(
        ..model,
        profile: p,
        hangar: Some(
          Hangar(..h, pick: case left {
            True -> h.pick
            False -> NoHangarPick
          }),
        ),
        news: "Sold " <> blueprint.describe(b) <> ".",
      )
    }
    Error(e) -> flash(model, describe_profile_error(e))
  }
}

pub fn update_hangar(model: Model, f: fn(Hangar) -> Hangar) -> Model {
  case model.hangar {
    Some(h) -> Model(..model, hangar: Some(f(h)))
    None -> model
  }
}

/// Save the design and start a run with the fabricated robots.
pub fn start_run(model: Model) -> Model {
  case model.hangar {
    None -> model
    Some(h) -> {
      let started = {
        use p <- result.try(
          list.index_fold(h.designs, Ok(model.profile), fn(acc, d, i) {
            result.try(acc, profile.set_design(_, i, d))
          }),
        )
        use run <- result.map(profile.start(p, browser.random_seed()))
        #(p, run)
      }
      case started {
        Ok(#(p, run)) -> {
          browser.save_profile(profile.encode(p))
          keep(run)
          new_model(run, p, None, model.now)
        }
        Error(e) -> flash(model, describe_profile_error(e))
      }
    }
  }
}
