import gleam/list
import gleam/option.{None, Some}
import robots/content/components
import robots/meta/blueprint.{ChassisBlueprint, PartBlueprint}
import robots/meta/profile.{Design, Profile}
import robots/rules/rng
import robots/run/map
import robots/run/state.{Bot, Run}

pub fn a_new_profile_fabricates_the_tinker_test() {
  let p = profile.new()
  let assert Ok(run) = profile.start(p, 1)
  let assert [bot] = run.robots
  assert bot.name == "Tinker"
  assert bot.chassis == components.frame()
  assert run.truck == 2
  // One copy of each blueprint the Tinker uses: two Platings.
  assert profile.copies(profile.new(), PartBlueprint("Laser")) == 1
  assert profile.copies(profile.new(), PartBlueprint("Plating")) == 2
}

pub fn research_takes_salvage_and_unlocks_the_blueprint_test() {
  let railgun = PartBlueprint("Railgun")
  let p = Profile(..profile.new(), data: 1000, found: [railgun])
  let assert Ok(after) = profile.research(p, railgun)
  assert after.data == 1000 - blueprint.research_cost(railgun)
  assert profile.copies(after, railgun) == 1
  assert after.found == []
  // Only found blueprints, and only with the Data for it.
  let assert Error(profile.NotFound(_)) = profile.research(after, railgun)
  let assert Error(profile.NotFound(_)) =
    profile.research(p, PartBlueprint("Cannon"))
  let assert Error(profile.NotEnoughData(..)) =
    profile.research(Profile(..p, data: 0), railgun)
}

pub fn a_design_needs_researched_blueprints_and_a_legal_build_test() {
  let p = profile.new()
  let gunner = Design("Gunner", "Frame", ["Machine gun", "Cell"])
  let assert Error(profile.NotResearched(PartBlueprint("Machine gun"))) =
    profile.set_design(p, 0, gunner)
  let p =
    Profile(..p, researched: [
      PartBlueprint("Machine gun"),
      PartBlueprint("Cell"),
      ..p.researched
    ])
  let assert Ok(p) = profile.set_design(p, 0, gunner)
  let assert Ok(run) = profile.start(p, 1)
  let assert [bot] = run.robots
  assert bot.name == "Gunner"
  // No battery: not a legal build.
  let assert Error(profile.CantBuild(..)) =
    profile.set_design(p, 0, Design("Bad", "Frame", ["Machine gun"]))
}

pub fn one_blueprint_makes_one_part_test() {
  let p = profile.new()
  let assert [tinker] = p.designs
  // A second Laser needs a second Laser blueprint.
  // One Plating fewer, to keep the weight.
  let twin = Design(..tinker, parts: ["Laser", ..list.take(tinker.parts, 4)])
  let assert Error(profile.NotEnoughCopies(PartBlueprint("Laser"), 1, 2)) =
    profile.set_design(p, 0, twin)
  let p2 = Profile(..p, researched: [PartBlueprint("Laser"), ..p.researched])
  let assert Ok(_) = profile.set_design(p2, 0, twin)
}

pub fn the_fabricator_builds_only_as_many_robots_as_it_can_test() {
  let p = profile.new()
  let assert [tinker] = p.designs
  let p = Profile(..p, designs: [tinker, Design(..tinker, name: "Second")])
  let assert Ok(run) = profile.start(p, 1)
  assert list.length(run.robots) == 1
  // Two robots need two copies of everything they're built from.
  let assert Error(profile.NotEnoughCopies(..)) =
    profile.start(Profile(..p, fabricator: 2), 1)
  let p =
    Profile(
      ..p,
      fabricator: 2,
      researched: list.append(p.researched, p.researched),
    )
  let assert Ok(run) = profile.start(p, 1)
  assert list.map(run.robots, fn(b) { b.name }) == ["Tinker", "Second"]
}

pub fn the_copier_copies_researched_blueprints_test() {
  let laser = PartBlueprint("Laser")
  let p = Profile(..profile.new(), data: 1000)
  let assert Error(profile.NoCopier) = profile.copy(p, laser)
  let assert Ok(p) = profile.research_copier(p)
  assert p.data == 1000 - profile.copier_cost
  let assert Error(profile.CopierResearched) = profile.research_copier(p)
  let assert Ok(after) = profile.copy(p, laser)
  assert profile.copies(after, laser) == 2
  assert after.data == p.data - profile.copy_cost(laser)
  assert profile.copy_cost(laser) > blueprint.research_cost(laser)
  // Only blueprints it has.
  let assert Error(profile.NotResearched(_)) =
    profile.copy(p, PartBlueprint("Cannon"))
}

pub fn a_duplicate_blueprint_is_one_more_copy_test() {
  let laser = PartBlueprint("Laser")
  let p = Profile(..profile.new(), data: 1000, found: [laser])
  let assert Ok(p) = profile.research(p, laser)
  assert profile.copies(p, laser) == 2
}

pub fn a_finished_run_pays_salvage_and_keeps_its_blueprints_test() {
  let p = profile.new()
  let assert Ok(run) = profile.start(p, 1)
  let run =
    Run(
      ..run,
      phase: state.Over,
      level: 2,
      money: 45,
      wins: [map.Boss, map.Strong, map.Normal, map.Normal],
      found: [PartBlueprint("Railgun")],
    )
  // Wins 10 + 3 + 1 + 1, one level past the first 5, scrap 45 / 20 = 2.
  assert state.data(run) == 22
  let e = profile.earnings(p, run)
  assert e.bonus == profile.first_boss_bonus
  let after = profile.finish(p, run)
  assert after.data == 22 + profile.first_boss_bonus
  assert after.found == [PartBlueprint("Railgun")]
  assert after.best_level == 1
  assert after.runs == 1
  // The first-boss bonus is paid once.
  assert profile.earnings(after, run).bonus == 0
}

pub fn a_profile_survives_saving_test() {
  let p =
    Profile(
      ..profile.new(),
      data: 37,
      found: [PartBlueprint("Railgun"), ChassisBlueprint("Scout")],
      truck: 3,
      copier: True,
      best_level: 1,
      runs: 4,
    )
  assert profile.decode(profile.encode(p)) == Ok(p)
  assert profile.decode("") == Error(Nil)
  assert profile.decode("garbage") == Error(Nil)
}

pub fn a_saved_profile_forgets_what_left_the_game_test() {
  let text =
    profile.encode(
      Profile(..profile.new(), found: [
        PartBlueprint("Railgun"),
        PartBlueprint("Gone gun"),
      ]),
    )
  let assert Ok(p) = profile.decode(text)
  assert p.found == [PartBlueprint("Railgun")]
}

pub fn bosses_always_drop_a_blueprint_test() {
  list.each([1, 2, 3, 4, 5], fn(seed) {
    let #(drop, _) = blueprint.roll(1, map.Boss, rng.new(seed))
    let assert Some(b) = drop
    assert blueprint.exists(b)
  })
  let #(drop, _) = blueprint.roll(1, map.Normal, rng.new(1))
  assert drop == None
}

pub fn strong_enemies_sometimes_drop_a_blueprint_test() {
  let #(_, drops) =
    list.map_fold(list.repeat(Nil, 400), rng.new(7), fn(seed, _) {
      let #(drop, seed) = blueprint.roll(1, map.Strong, seed)
      #(seed, drop)
    })
  let share = list.length(option.values(drops)) * 100 / 400
  assert share >= blueprint.strong_percent - 6
  assert share <= blueprint.strong_percent + 6
}

pub fn the_truck_limits_the_robots_test() {
  let run = state.new(1)
  let tinker = Bot("Tinker", components.frame(), [])
  let full = Run(..run, robots: [tinker, tinker], chassis: [components.frame()])
  let assert Error(state.TruckFull(2)) = state.assemble(full, "Third", 0, [])
}

pub fn an_old_save_keeps_the_starter_blueprints_test() {
  // Saved before blueprints made one part each: a single Plating.
  let old =
    "version:1\nsalvage:5\nresearched:c:Frame|p:Laser|p:Buckler|p:Big capacitor|p:Plating\nfound:\ntruck:2\nfabricator:1\nbest_level:0\nruns:2\ndesigns:Tinker/Frame/Laser;Buckler;Big capacitor;Plating;Plating"
  let assert Ok(p) = profile.decode(old)
  assert profile.copies(p, PartBlueprint("Plating")) == 2
  let assert Ok(_) = profile.start(p, 1)
}

pub fn a_profile_saved_with_salvage_keeps_it_as_data_test() {
  let old =
    "version:1\nsalvage:42\nresearched:c:Frame|p:Laser|p:Buckler|p:Big capacitor|p:Plating|p:Plating\nfound:\ntruck:2\nfabricator:1\nbest_level:0\nruns:2\ndesigns:Tinker/Frame/Laser;Buckler;Big capacitor;Plating;Plating"
  let assert Ok(p) = profile.decode(old)
  assert p.data == 42
}
