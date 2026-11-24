import gleam/int
import gleam/list
import gleam/option
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

pub fn loot_is_never_worse_than_new_test() {
  let bad = ["Broken", "Damaged", "Weak", "Crude", "Wasteful"]
  list.each([1, 2, 3], fn(level) {
    let #(drops, _) = loot.rolls(level, 200, rng.new(level))
    list.each(drops, fn(d) {
      list.each(d.attributes, fn(pair) {
        assert !list.contains(bad, { pair.1 }.name)
      })
    })
  })
}

pub fn armor_never_gets_gun_words_test() {
  // Precise, Rapid... make no sense on a plate; they never go on one.
  let #(drops, _) = loot.rolls(3, 400, rng.new(9))
  let armor_words = ["Hardened", "Thick", "Masterwork", "Scratched"]
  list.each(drops, fn(d) {
    case d.kind {
      part.Armor ->
        list.each(d.attributes, fn(pair) {
          let assert Ok(w) = part.attribute_word(part.Armor, pair.1)
          assert list.contains(armor_words, w)
        })
      _ -> Nil
    }
  })
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

pub fn strong_enemies_sometimes_drop_a_cheap_chassis_test() {
  let #(_, drops) =
    list.map_fold(list.repeat(Nil, 400), rng.new(9), fn(seed, _) {
      let #(drop, seed) = loot.strong_chassis(1, seed)
      #(seed, drop)
    })
  let chassis = option.values(drops)
  // About strong_chassis_percent of the time, always a level 1 cheap one.
  let share = list.length(chassis) * 100 / 400
  assert share > loot.strong_chassis_percent - 8
  assert share < loot.strong_chassis_percent + 8
  assert list.all(chassis, fn(c) { c == components.mosquito() })
}
