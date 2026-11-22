import gleam/list
import robots/construction/builder.{
  DeadCard, DeckTooSmall, NoBattery, NoWeapon, Overweight, TooManyWeapons,
  Unaffordable, WeaponTooHeavy,
}
import robots/construction/part
import robots/construction/robot
import robots/content/catalog
import robots/rules/card.{Attack, Card, Defence, One, Opponent, OpponentHp}

// STARTERS --------------------------------------------------------------------

pub fn starters_use_different_chassis_test() {
  assert catalog.tinker().chassis == "Frame"
  assert catalog.scrapper().chassis == "Brute"
}

/// A chassis with no cards of its own, for deck-size tests.
fn bare() -> builder.Chassis {
  builder.Chassis(..catalog.frame(), name: "Bare", cards: [])
}

/// The chassis plus 16 filler cards, so tests of other rules aren't tripped
/// by the minimum deck size. Fillers are defences: never dead, never buffed.
fn padded(chassis: builder.Chassis) -> builder.Chassis {
  let filler =
    Card("Filler", [Defence], 0.5, 0.38, Opponent(One([Attack])), traits: [])
  builder.Chassis(
    ..chassis,
    cards: list.append(chassis.cards, list.repeat(filler, 16)),
  )
}

pub fn chassis_cards_join_every_deck_test() {
  let assert Ok(bot) =
    builder.build("B", catalog.scout(), [
      catalog.machine_gun(),
      catalog.machine_gun(),
      catalog.machine_gun(),
      catalog.cell(),
    ])
  let names = list.map(robot.deck(bot), fn(c) { c.name })
  assert list.take(names, 5) == ["Jump", "Jump", "Dodge", "Dodge", "Burst"]
  // 4 chassis cards and 5 per Machine gun.
  assert list.length(names) == 19
}

pub fn armor_adds_block_cards_test() {
  let assert Ok(bot) =
    builder.build("B", padded(bare()), [
      catalog.laser(),
      catalog.cell(),
      catalog.plating(),
      catalog.heavy_plating(),
    ])
  let blocks = list.count(robot.deck(bot), fn(c) { c.name == "Block" })
  assert blocks == 3
}

pub fn starters_have_no_warnings_test() {
  assert builder.warnings(catalog.tinker()) == []
  assert builder.warnings(catalog.scrapper()) == []
}

pub fn every_chassis_has_a_legal_signature_build_test() {
  let assert Ok(_) =
    builder.build("Tank", catalog.tank(), [
      catalog.cannon(),
      catalog.cell(),
      catalog.kinetic_shield(),
      catalog.deflector(),
      catalog.buckler(),
      catalog.heavy_plating(),
    ])
  let assert Ok(_) =
    builder.build("Scout", catalog.scout(), [
      catalog.machine_gun(),
      catalog.machine_gun(),
      catalog.machine_gun(),
      catalog.cell(),
    ])
  let assert Ok(_) =
    builder.build("Brute", catalog.brute(), [
      catalog.saw_arm(),
      catalog.fist(),
      catalog.hydraulics(),
      catalog.deflector(),
      catalog.battery(),
    ])
}

// STATS -----------------------------------------------------------------------

pub fn armor_adds_hp_and_batteries_stack_test() {
  let assert Ok(bot) =
    builder.build("B", padded(catalog.frame()), [
      catalog.laser(),
      catalog.fist(),
      catalog.cell(),
      catalog.battery(),
      catalog.plating(),
    ])
  assert bot.max_hp == 9.0 +. 2.5
  assert bot.hp == bot.max_hp
  assert bot.energy_cap == 8.0
}

// ERRORS ----------------------------------------------------------------------

pub fn overweight_is_rejected_test() {
  // Frame carries 12: 3 + 1 + 2 + 4 + 4 = 14.
  assert builder.build("B", padded(catalog.frame()), [
      catalog.laser(),
      catalog.fist(),
      catalog.battery(),
      catalog.heavy_plating(),
      catalog.heavy_plating(),
    ])
    == Error([Overweight(total: 14.0, capacity: 12.0)])
}

pub fn light_parts_make_room_test() {
  // The same build fits when the Heavy platings are Light (4 → 3 each).
  let light_plating = catalog.heavy_plating() |> part.with(part.light())
  let assert Ok(bot) =
    builder.build("B", padded(catalog.frame()), [
      catalog.laser(),
      catalog.fist(),
      catalog.battery(),
      light_plating,
      light_plating,
    ])
  // Light changes weight only, not HP.
  assert bot.max_hp == 9.0 +. 10.0
}

pub fn too_many_weapons_is_rejected_test() {
  assert builder.build("B", padded(catalog.frame()), [
      catalog.fist(),
      catalog.fist(),
      catalog.fist(),
      catalog.battery(),
    ])
    == Error([TooManyWeapons(count: 3, mounts: 2)])
}

pub fn weapon_too_heavy_for_any_mount_is_rejected_test() {
  assert builder.build("B", padded(catalog.frame()), [
      catalog.cannon(),
      catalog.fist(),
      catalog.battery(),
    ])
    == Error([WeaponTooHeavy(weapon: "Cannon", weight: 6.0, mount_limit: 4.0)])
}

pub fn weapons_are_matched_to_mounts_by_size_test() {
  // Brute has mounts 4 and 2: a Saw arm (3) and a Fist (1) fit, two Saw
  // arms don't, because the second would need the small mount.
  let assert Ok(_) =
    builder.build("B", padded(catalog.brute()), [
      catalog.fist(),
      catalog.saw_arm(),
      catalog.battery(),
    ])
  assert builder.build("B", padded(catalog.brute()), [
      catalog.saw_arm(),
      catalog.saw_arm(),
      catalog.battery(),
    ])
    == Error([WeaponTooHeavy(weapon: "Saw arm", weight: 3.0, mount_limit: 2.0)])
}

pub fn a_battery_is_required_test() {
  assert builder.build("B", padded(catalog.frame()), [
      catalog.laser(),
      catalog.fist(),
    ])
    == Error([NoBattery])
}

/// A weapon with a single card, for deck-size tests.
fn one_shot(weight: Float) -> part.Component {
  let shot = Card("Shot", [Attack], 1.0, 1.0, OpponentHp, traits: [])
  part.new("One-shot", part.Weapon, weight, [shot])
}

pub fn a_robot_needs_sixteen_cards_test() {
  assert builder.build("B", bare(), [
      catalog.battery(),
      catalog.plating(),
      one_shot(1.0),
    ])
    == Error([DeckTooSmall(cards: 2, minimum: 16)])
}

pub fn all_problems_are_reported_together_test() {
  let assert Error(errors) =
    builder.build("B", builder.Chassis(..catalog.scout(), cards: []), [
      one_shot(6.0),
    ])
  assert list.length(errors) == 3
  assert list.contains(errors, NoBattery)
  assert list.contains(errors, DeckTooSmall(cards: 1, minimum: 16))
  assert list.contains(
    errors,
    WeaponTooHeavy(weapon: "One-shot", weight: 6.0, mount_limit: 2.0),
  )
}

// MODIFIERS -------------------------------------------------------------------

pub fn overclocked_parts_are_stronger_test() {
  let hot = catalog.laser() |> part.with(part.overclocked())
  let values = list.map(part.cards(hot), fn(c) { c.value })
  assert values == list.map(catalog.laser().cards, fn(c) { c.value *. 1.15 })
  // Costs and weight don't change.
  assert list.map(part.cards(hot), fn(c) { c.cost })
    == list.map(catalog.laser().cards, fn(c) { c.cost })
  assert part.weight(hot) == 3.0
  // Overclocked armor gives more HP.
  assert part.hp(catalog.plating() |> part.with(part.overclocked()))
    == 2.5 *. 1.15
}

pub fn modifiers_stack_and_name_the_part_test() {
  let loot =
    catalog.laser()
    |> part.with(part.light())
    |> part.with(part.overclocked())
  assert part.display_name(loot) == "Light Overclocked Laser"
  assert part.weight(loot) == 2.25
}

// WARNINGS --------------------------------------------------------------------

pub fn buff_without_matching_own_cards_is_dead_test() {
  // Lock on raises [attack, range] cards; a Saw arm is melee only.
  let assert Ok(bot) =
    builder.build("B", padded(catalog.frame()), [
      catalog.saw_arm(),
      catalog.targeting_computer(),
      catalog.battery(),
    ])
  assert builder.warnings(bot)
    == [
      DeadCard(card: "Quick lock"),
      DeadCard(card: "Lock on"),
      DeadCard(card: "Full lock"),
    ]
}

pub fn card_costing_more_than_the_batteries_hold_is_flagged_test() {
  let nuke = Card("Nuke", [Attack], 4.0, 4.0, OpponentHp, traits: [])
  let bot =
    robot.new("B", chassis: "Test", max_hp: 5.0, energy_cap: 3.0, components: [
      part.new("Launcher", part.Weapon, 1.0, [nuke, nuke]),
    ])
  assert builder.warnings(bot)
    == [Unaffordable(card: "Nuke", cost: 4.0, cap: 3.0)]
}

pub fn a_weapon_is_required_test() {
  // The Frame's own Kick isn't enough.
  assert builder.build("B", padded(catalog.frame()), [
      catalog.kinetic_shield(),
      catalog.deflector(),
      catalog.battery(),
    ])
    == Error([NoWeapon])
}
