import gleam/list
import robots/construction/builder
import robots/construction/part.{type Component, Component}
import robots/construction/wear
import robots/content/catalog

/// An armor plate with 2 HP.
fn plate(name: String, worn: Float) -> Component {
  Component(..part.armor(name, 1.0, 2.0, []), wear: worn)
}

fn wear_of(parts: List(Component)) -> List(#(String, Float)) {
  list.map(parts, fn(p) { #(p.name, p.wear) })
}

pub fn plates_break_one_at_a_time_test() {
  // Three 2-HP plates and 5 damage: two break, the third is at 50%.
  let parts = [
    catalog.laser(),
    plate("A", 0.0),
    plate("B", 0.0),
    plate("C", 0.0),
  ]
  let #(chassis, parts) = wear.assign(catalog.frame(), parts, 5.0)
  assert wear_of(parts) == [#("Laser", 0.0), #("C", 1.0)]
  assert chassis.wear == 0.0
}

pub fn the_most_worn_plate_goes_first_test() {
  let parts = [plate("Fresh", 0.0), plate("Worn", 1.5)]
  let #(_, parts) = wear.assign(catalog.frame(), parts, 1.0)
  // Worn (0.5 left) breaks; the remaining 0.5 goes on Fresh.
  assert wear_of(parts) == [#("Fresh", 0.5)]
}

pub fn damage_beyond_the_armor_hits_the_chassis_test() {
  let #(chassis, parts) = wear.assign(catalog.frame(), [plate("A", 0.0)], 5.0)
  assert parts == []
  assert chassis.wear == 3.0
}

pub fn chassis_wear_never_exceeds_its_hp_test() {
  let #(chassis, _) = wear.assign(catalog.frame(), [], 100.0)
  assert chassis.wear == catalog.frame().hp
  assert builder.chassis_hp(chassis) == 0.0
}

pub fn a_robot_starts_with_what_its_worn_parts_have_left_test() {
  let fresh = catalog.tinker()
  let worn_frame = builder.Chassis(..catalog.frame(), wear: 2.0)
  let worn_plating =
    Component(..part.with(catalog.plating(), part.overclocked()), wear: 1.0)
  let assert Ok(worn) =
    builder.build("Tinker", worn_frame, [
      catalog.laser(),
      catalog.buckler(),
      catalog.reactor(),
      catalog.big_battery(),
      worn_plating,
    ])
  // Max HP counts parts as new; current HP is 3.0 lower.
  assert worn.max_hp == fresh.max_hp
  assert worn.hp == fresh.hp -. 3.0
}
