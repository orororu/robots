import gleam/int
import gleam/list
import robots/construction/builder
import robots/construction/part.{Component}
import robots/content/components
import robots/rules/rng
import robots/run/loot
import robots/run/price

pub fn every_level_has_a_chart_with_positive_weights_test() {
  list.each(loot.charts(), fn(ch) {
    assert ch.entries != []
    assert list.all(ch.entries, fn(e) { e.0 > 0 })
  })
}

pub fn levels_past_the_last_use_the_last_chart_test() {
  let assert Ok(last) = list.last(loot.charts())
  assert loot.chart(99) == last
  assert loot.chart(0).level == 1
}

pub fn rolls_are_reproducible_and_from_the_chart_test() {
  let #(a, _) = loot.rolls(1, 20, rng.new(7))
  let #(b, _) = loot.rolls(1, 20, rng.new(7))
  assert a == b
  let names = list.map(loot.chart(1).entries, fn(e) { { e.1 }.name })
  assert list.all(a, fn(drop) { list.contains(names, drop.name) })
}

pub fn every_part_has_a_price_test() {
  assert list.all(components.all(), fn(c) { price.of(c) > 0 })
}

pub fn modifiers_raise_and_wear_lowers_the_price_test() {
  let plating = components.plating()
  assert price.of(part.with(plating, part.light())) > price.of(plating)
  assert price.of(part.with(plating, part.overclocked())) > price.of(plating)
  assert price.of(Component(..plating, wear: 1.0)) < price.of(plating)
}

pub fn heavier_parts_cost_less_for_the_same_cards_test() {
  let laser = components.laser()
  assert price.of(Component(..laser, weight: 4.0)) < price.of(laser)
}

pub fn a_battle_drops_one_to_three_parts_test() {
  let counts =
    list.map(int.range(1, 41, [], list.prepend), fn(i) {
      let #(drops, _) = loot.battle_drops(1, rng.new(i))
      list.length(drops)
    })
  assert list.all(counts, fn(n) { n >= 1 && n <= 3 })
  assert list.contains(counts, 1) && list.contains(counts, 3)
}

pub fn chassis_cost_more_than_any_part_test() {
  let priciest =
    list.fold(components.all(), 0, fn(m, c) { int.max(m, price.of(c)) })
  assert list.all(components.chassis(), fn(ch) {
    price.of_chassis(ch) > priciest
  })
}

pub fn bigger_chassis_cost_more_test() {
  let frame = components.frame()
  assert price.of_chassis(builder.Chassis(..frame, capacity: 16.0))
    > price.of_chassis(frame)
  assert price.of_chassis(builder.Chassis(..frame, wear: 3.0))
    < price.of_chassis(frame)
}

pub fn bosses_drop_a_chassis_from_their_chart_test() {
  let #(ch, _) = loot.boss_chassis(1, rng.new(3))
  assert list.contains(loot.chart(1).boss_chassis, ch)
}
