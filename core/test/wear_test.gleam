import gleam/list
import robots/construction/builder
import robots/construction/part.{type Component, Component}
import robots/construction/wear
import robots/content/cards
import robots/content/components
import robots/content/starters

/// An armor plate with 2 HP and a Block card.
fn plate(name: String, worn: Float) -> Component {
  Component(..part.armor(name, 1.0, 2.0, [cards.block()]), wear: worn)
}

fn wear_of(parts: List(Component)) -> List(#(String, Float)) {
  list.map(parts, fn(p) { #(p.name, p.wear) })
}

pub fn plates_break_one_at_a_time_test() {
  // Three 2-HP plates and 5 damage: two break, the third is at 50%.
  let parts = [
    components.laser(),
    plate("A", 0.0),
    plate("B", 0.0),
    plate("C", 0.0),
  ]
  let #(chassis, parts) = wear.assign(components.frame(), parts, 5.0)
  assert wear_of(parts)
    == [#("Laser", 0.0), #("A", 2.0), #("B", 2.0), #("C", 1.0)]
  assert list.map(parts, wear.is_broken) == [False, True, True, False]
  assert chassis.wear == 0.0
}

pub fn the_most_worn_plate_goes_first_test() {
  let parts = [plate("Fresh", 0.0), plate("Worn", 1.5)]
  let #(_, parts) = wear.assign(components.frame(), parts, 1.0)
  // Worn (0.5 left) breaks; the remaining 0.5 goes on Fresh.
  assert wear_of(parts) == [#("Fresh", 0.5), #("Worn", 2.0)]
}

pub fn damage_beyond_the_armor_hits_the_chassis_test() {
  let #(chassis, parts) =
    wear.assign(components.frame(), [plate("A", 0.0)], 5.0)
  assert wear_of(parts) == [#("A", 2.0)]
  assert chassis.wear == 3.0
}

pub fn a_broken_plate_keeps_its_cards_but_broken_test() {
  let #(_, parts) = wear.assign(components.frame(), [components.plating()], 3.0)
  let assert [broken] = parts
  assert part.remaining_hp(broken) == 0.0
  assert part.display_name(broken) == "Broken plating"
  let assert [block] = part.cards(broken)
  assert block.name == "Broken Block"
  // A broken plate takes no more damage: it all goes to the chassis.
  let #(chassis, _) = wear.assign(components.frame(), parts, 1.0)
  assert chassis.wear == 1.0
}

pub fn a_worn_robot_keeps_its_deck_size_test() {
  let frame = components.frame()
  let parts = [
    components.laser(),
    components.buckler(),
    components.reactor(),
    components.big_battery(),
    components.plating(),
  ]
  let #(frame, parts) = wear.assign(frame, parts, 4.0)
  // The plating broke, but its Block stays: still a legal 16-card deck.
  let assert Ok(bot) = builder.build("Tinker", frame, parts)
  // 2.5 went on the plating, 1.5 on the Frame (9 HP): 7.5 left.
  assert bot.hp == 7.5
}

pub fn chassis_wear_never_exceeds_its_hp_test() {
  let #(chassis, _) = wear.assign(components.frame(), [], 100.0)
  assert chassis.wear == components.frame().hp
  assert builder.chassis_hp(chassis) == 0.0
}

pub fn a_robot_starts_with_what_its_worn_parts_have_left_test() {
  let fresh = starters.tinker()
  let worn_frame = builder.Chassis(..components.frame(), wear: 2.0)
  let worn_plating =
    Component(..part.with(components.plating(), part.overclocked()), wear: 1.0)
  let assert Ok(worn) =
    builder.build("Tinker", worn_frame, [
      components.laser(),
      components.buckler(),
      components.reactor(),
      components.big_battery(),
      worn_plating,
    ])
  // Max HP counts parts as new; current HP is 3.0 lower.
  assert worn.max_hp == fresh.max_hp
  assert worn.hp == fresh.hp -. 3.0
}
