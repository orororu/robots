import gleam/list
import gleam/option.{None, Some}
import robots/construction/attribute
import robots/construction/part
import robots/content/components
import robots/meta/blueprint.{
  ChassisBlueprint, FabricatorBlueprint, PartBlueprint,
}
import robots/meta/profile.{Design, Profile}
import robots/rules/rng
import robots/run/map
import robots/run/state.{Bot, Run}

/// The plain blueprint of a part.
fn bp(p: part.Component) {
  blueprint.of_part(p)
}

/// A Laser whose first two cards are tuned up: a different blueprint.
fn rapid_laser() {
  components.laser()
  |> part.attach(0, attribute.rapid())
  |> part.attach(1, attribute.precise())
}

pub fn a_new_profile_fabricates_the_tinker_test() {
  let p = profile.new()
  let assert Ok(run) = profile.start(p, 1)
  let assert [bot] = run.robots
  assert bot.name == "Tinker"
  assert bot.chassis == components.frame()
  assert run.truck == 2
  // One copy of each blueprint the Tinker uses: two Platings.
  assert profile.copies(p, bp(components.laser())) == 1
  assert profile.copies(p, bp(components.plating())) == 2
}

pub fn research_takes_data_and_unlocks_the_blueprint_test() {
  let railgun = bp(components.railgun())
  let p = Profile(..profile.new(), data: 1000, found: [railgun])
  let assert Ok(after) = profile.research(p, railgun)
  assert after.data == 1000 - blueprint.research_cost(railgun)
  assert profile.copies(after, railgun) == 1
  assert after.found == []
  // Only found blueprints, and only with the Data for it.
  let assert Error(profile.NotFound(_)) = profile.research(after, railgun)
  let assert Error(profile.NotFound(_)) =
    profile.research(p, bp(components.cannon()))
  let assert Error(profile.NotEnoughData(..)) =
    profile.research(Profile(..p, data: 0), railgun)
}

pub fn a_design_needs_researched_blueprints_and_a_legal_build_test() {
  let p = profile.new()
  let gunner =
    Design("Gunner", "Frame", [components.machine_gun(), components.cell()])
  let assert Error(profile.NotResearched(PartBlueprint(_))) =
    profile.set_design(p, 0, gunner)
  let p =
    Profile(..p, researched: [
      bp(components.machine_gun()),
      bp(components.cell()),
      ..p.researched
    ])
  let assert Ok(p) = profile.set_design(p, 0, gunner)
  let assert Ok(run) = profile.start(p, 1)
  let assert [bot] = run.robots
  assert bot.name == "Gunner"
  // No battery: not a legal build.
  let assert Error(profile.CantBuild(..)) =
    profile.set_design(p, 0, Design("Bad", "Frame", [components.machine_gun()]))
}

pub fn one_blueprint_makes_one_part_test() {
  let p = profile.new()
  let assert [tinker] = p.designs
  // A second Laser needs a second Laser blueprint (one Plating fewer, to
  // keep the weight).
  let twin =
    Design(..tinker, parts: [components.laser(), ..list.take(tinker.parts, 4)])
  let assert Error(profile.NotEnoughCopies(PartBlueprint(_), 1, 2)) =
    profile.set_design(p, 0, twin)
  let p2 = Profile(..p, researched: [bp(components.laser()), ..p.researched])
  let assert Ok(_) = profile.set_design(p2, 0, twin)
}

pub fn a_better_part_is_its_own_blueprint_test() {
  let p = profile.new()
  let assert [tinker] = p.designs
  let better =
    Design(..tinker, parts: [rapid_laser(), ..list.drop(tinker.parts, 1)])
  // The plain Laser's blueprint doesn't make a Rapid one.
  let assert Error(profile.NotResearched(_)) = profile.set_design(p, 0, better)
  let p = Profile(..p, data: 1000, found: [bp(rapid_laser())])
  let assert Ok(p) = profile.research(p, bp(rapid_laser()))
  let assert Ok(p) = profile.set_design(p, 0, better)
  // The fabricator builds it with its attributes.
  let assert Ok(run) = profile.start(p, 1)
  let assert [bot] = run.robots
  assert list.contains(bot.parts, rapid_laser())
  // Much stronger parts cost more to research.
  let strong =
    components.laser()
    |> part.attach(2, attribute.masterwork())
    |> part.attach(3, attribute.masterwork())
    |> part.attach(4, attribute.masterwork())
  assert blueprint.research_cost(bp(strong))
    > blueprint.research_cost(bp(components.laser()))
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

pub fn a_duplicate_blueprint_is_one_more_copy_test() {
  let laser = bp(components.laser())
  let p = Profile(..profile.new(), data: 1000, found: [laser])
  let assert Ok(p) = profile.research(p, laser)
  assert profile.copies(p, laser) == 2
}

pub fn a_finished_run_pays_data_and_keeps_its_blueprints_test() {
  let p = profile.new()
  let assert Ok(run) = profile.start(p, 1)
  let railgun = bp(components.railgun())
  let run =
    Run(
      ..run,
      phase: state.Over,
      level: 2,
      money: 45,
      wins: [map.Boss, map.Strong, map.Normal, map.Normal],
      found: [railgun],
    )
  // Wins 10 + 3 + 1 + 1, one level past the first 5, scrap 45 / 20 = 2.
  assert state.data(run) == 22
  let e = profile.earnings(p, run)
  assert e.bonus == profile.first_boss_bonus
  let after = profile.finish(p, run)
  assert after.data == 22 + profile.first_boss_bonus
  assert after.found == [railgun]
  assert after.best_level == 1
  assert after.runs == 1
  // The first-boss bonus is paid once.
  assert profile.earnings(after, run).bonus == 0
}

pub fn a_profile_survives_saving_test() {
  let light_rapid = rapid_laser() |> part.with(part.light())
  let base = profile.new()
  let assert [tinker] = base.designs
  let p =
    Profile(
      ..base,
      data: 37,
      researched: [bp(light_rapid), ..base.researched],
      found: [bp(components.railgun()), ChassisBlueprint("Scout")],
      designs: [
        Design(..tinker, parts: [light_rapid, ..list.drop(tinker.parts, 1)]),
      ],
      truck: 3,
      best_level: 1,
      runs: 4,
    )
  assert profile.decode(profile.encode(p)) == Ok(p)
  assert profile.decode("") == Error(Nil)
  assert profile.decode("garbage") == Error(Nil)
}

pub fn a_saved_profile_forgets_what_left_the_game_test() {
  let text =
    profile.encode(Profile(..profile.new(), found: [bp(components.railgun())]))
    <> "|p:Gone gun|p:Laser+0=Gone attribute"
  let assert Ok(p) = profile.decode(text)
  assert p.found == [bp(components.railgun())]
}

pub fn bosses_always_drop_a_blueprint_test() {
  list.each([1, 2, 3, 4, 5], fn(seed) {
    let #(drop, _) = blueprint.roll(1, map.Boss, 1, rng.new(seed))
    let assert Some(b) = drop
    assert blueprint.exists(b)
  })
  let #(drop, _) = blueprint.roll(1, map.Normal, 1, rng.new(1))
  assert drop == None
}

pub fn blueprints_come_in_different_qualities_test() {
  let #(_, drops) =
    list.map_fold(list.repeat(Nil, 200), rng.new(3), fn(seed, _) {
      let #(drop, seed) =
        blueprint.roll(2, map.Boss, blueprint.max_fabricator, seed)
      #(seed, drop)
    })
  let parts =
    list.filter_map(option.values(drops), fn(b) {
      case b {
        PartBlueprint(p) -> Ok(p)
        ChassisBlueprint(_) | FabricatorBlueprint -> Error(Nil)
      }
    })
  assert list.any(parts, fn(p) { p.attributes != [] })
  assert list.any(parts, fn(p) { p.attributes == [] && p.modifiers == [] })
  // New, whatever the loot was.
  assert list.all(parts, fn(p) { p.wear == 0.0 })
}

pub fn strong_enemies_sometimes_drop_a_blueprint_test() {
  let #(_, drops) =
    list.map_fold(list.repeat(Nil, 400), rng.new(7), fn(seed, _) {
      let #(drop, seed) = blueprint.roll(1, map.Strong, 1, seed)
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

pub fn blueprints_sell_for_a_little_data_test() {
  let railgun = bp(components.railgun())
  let laser = bp(components.laser())
  let p = Profile(..profile.new(), found: [railgun])
  assert profile.sell_price(railgun) == blueprint.research_cost(railgun) / 5
  let assert Ok(after) = profile.sell_found(p, railgun)
  assert after.found == []
  assert after.data == profile.sell_price(railgun)
  let assert Error(profile.NotFound(_)) = profile.sell_found(after, railgun)
  // A component sells, the starting kit's too, unless a design needs every
  // one of it.
  let assert Error(profile.InUse(_)) =
    profile.sell_researched(profile.new(), laser)
  let assert [kit] = profile.new().designs
  let spare_laser =
    Profile(..profile.new(), researched: [laser, ..profile.new().researched])
  let assert Ok(_) = profile.sell_researched(spare_laser, laser)
  let no_laser =
    Profile(..profile.new(), designs: [
      Design(..kit, parts: [components.fist(), ..list.drop(kit.parts, 1)]),
    ])
  let assert Ok(sold_kit) = profile.sell_researched(no_laser, laser)
  // And it stays sold after saving.
  let assert Ok(back) = profile.decode(profile.encode(sold_kit))
  assert profile.copies(back, laser) == 0
  let extra =
    Profile(..profile.new(), researched: [railgun, ..profile.new().researched])
  let assert Ok(sold) = profile.sell_researched(extra, railgun)
  assert profile.copies(sold, railgun) == 0
  let assert [tinker] = extra.designs
  let uses =
    Profile(..extra, designs: [
      Design(..tinker, parts: [
        components.railgun(),
        ..list.drop(tinker.parts, 1)
      ]),
    ])
  let assert Error(profile.InUse(_)) = profile.sell_researched(uses, railgun)
}

pub fn bosses_sometimes_drop_the_fabricator_upgrade_test() {
  let drops = fn(fabricator) {
    let #(_, drops) =
      list.map_fold(list.repeat(Nil, 400), rng.new(11), fn(seed, _) {
        let #(drop, seed) = blueprint.roll(1, map.Boss, fabricator, seed)
        #(seed, drop)
      })
    list.count(drops, fn(d) { d == Some(FabricatorBlueprint) }) * 100 / 400
  }
  let share = drops(1)
  assert share >= blueprint.fabricator_percent - 6
  assert share <= blueprint.fabricator_percent + 6
  // Not once the fabricator is fully upgraded, and never from other enemies.
  assert drops(blueprint.max_fabricator) == 0
  let #(strong, _) = blueprint.roll(1, map.Strong, 1, rng.new(1))
  assert strong != Some(FabricatorBlueprint)
}

pub fn researching_the_fabricator_upgrade_builds_a_second_robot_test() {
  let p = Profile(..profile.new(), data: 200, found: [FabricatorBlueprint])
  let assert Ok(after) = profile.research(p, FabricatorBlueprint)
  assert after.fabricator == 2
  assert after.data == 200 - blueprint.fabricator_research
  assert after.found == []
  // It isn't a component: nothing to fabricate from it.
  assert profile.copies(after, FabricatorBlueprint) == 0
  // A run started from it knows: no more upgrades drop.
  let assert Ok(run) = profile.start(after, 1)
  assert run.fabricator == 2
  // A second one can only be sold.
  let again = Profile(..after, data: 200, found: [FabricatorBlueprint])
  let assert Error(profile.FabricatorFull) =
    profile.research(again, FabricatorBlueprint)
  let assert Ok(sold) = profile.sell_found(again, FabricatorBlueprint)
  assert sold.data == 200 + profile.sell_price(FabricatorBlueprint)
  // Saved and loaded like any blueprint.
  assert profile.decode(profile.encode(p)) == Ok(p)
}
