import gleam/float
import gleam/list
import robots/construction/attribute
import robots/construction/part
import robots/content/cards
import robots/content/components
import robots/content/enemies
import robots/rules/card.{type Card}
import robots/rules/rng
import robots/run/loot
import robots/run/price

fn nth(cards: List(Card), i: Int) -> Card {
  let assert [c, ..] = list.drop(cards, i)
  c
}

pub fn an_attribute_changes_the_card_and_its_name_test() {
  // Laser cards: Pulse, Laser, Laser, Focused beam, Overcharge.
  let gun = part.attach(components.laser(), 1, attribute.rapid())
  let c = nth(part.cards(gun), 1)
  assert c.name == "Rapid Laser"
  assert c.cost == 0.8
  assert c.value == 1.0
  // The other cards are untouched.
  assert nth(part.cards(gun), 2) == nth(components.laser().cards, 2)
}

pub fn a_card_has_at_most_one_attribute_test() {
  let gun =
    components.laser()
    |> part.attach(1, attribute.rapid())
    |> part.attach(1, attribute.broken())
  assert list.length(gun.attributes) == 1
  assert nth(part.cards(gun), 1).name == "Broken Laser"
}

pub fn value_attributes_skip_cards_whose_value_does_nothing_test() {
  // Drone bay cards launch drones: their own value is unused.
  let bay = part.attach(components.drone_bay(), 0, attribute.strong())
  assert bay.attributes == []
  let bay = part.attach(components.drone_bay(), 0, attribute.rapid())
  assert list.length(bay.attributes) == 1
}

pub fn precise_makes_a_bigger_card_on_the_band_test() {
  let base = nth(components.laser().cards, 1)
  let c = attribute.apply(attribute.precise(), base)
  assert c.cost >. base.cost
  // Bigger cards are more efficient: value grows faster than cost.
  assert c.value /. c.cost >. base.value /. base.cost
}

pub fn the_name_shows_the_two_most_impactful_attributes_test() {
  let gun =
    components.machine_gun()
    // Burst ×3, Long burst, Sweep. Worn on a small Burst changes little;
    // Rapid on Long burst and Broken on Sweep change more.
    |> part.attach(0, attribute.worn())
    |> part.attach(3, attribute.rapid())
    |> part.attach(4, attribute.broken())
  assert part.display_name(gun) == "Broken rapid machine gun"
}

pub fn attributes_change_the_price_test() {
  let gun = components.laser()
  assert price.of(part.attach(gun, 1, attribute.masterwork())) > price.of(gun)
  assert price.of(part.attach(gun, 1, attribute.broken())) < price.of(gun)
}

pub fn later_levels_roll_better_attributes_test() {
  // Average worth change of rolled attributes on many Laser drops.
  let average = fn(level) {
    let #(drops, _) = loot.rolls(level, 300, rng.new(5))
    let lasers = list.map(drops, fn(d) { price.of(d) })
    list.fold(lasers, 0, fn(t, p) { t + p }) / list.length(lasers)
  }
  assert average(3) > average(1)
}

pub fn spawned_enemies_are_named_after_their_parts_test() {
  let e = enemies.scrap_gunner()
  let bare = enemies.name(e)
  assert bare == "Scrap gunner"
  let #(spawned, _) = enemies.spawn(e, 1, 3, rng.new(11))
  // Spawning is reproducible.
  let #(again, _) = enemies.spawn(e, 1, 3, rng.new(11))
  assert spawned == again
  let _ = enemies.robot(spawned)
}

pub fn early_enemies_are_worn_down_test() {
  // Step 0: every card that a value attribute affects is Broken, Damaged
  // or Weak.
  let #(rusty, _) = enemies.spawn(enemies.rusty_brawler(), 1, 0, rng.new(5))
  let bad = ["Broken", "Damaged", "Weak"]
  list.each(rusty.parts, fn(p) {
    list.each(list.index_map(p.cards, fn(c, i) { #(i, c) }), fn(pair) {
      case attribute.applies_to(attribute.broken(), pair.1) {
        False -> Nil
        True -> {
          let assert Ok(a) = list.key_find(p.attributes, pair.0)
          assert list.contains(bad, a.name)
        }
      }
    })
  })
}

pub fn level_monsters_arrive_less_worn_test() {
  // A Junk fly at step 0 is built like any other robot at a later step.
  let fly = enemies.junk_fly()
  let plain = enemies.Enemy(..fly, name: "Not a monster")
  let #(met, _) = enemies.spawn(fly, 1, 0, rng.new(5))
  let #(fresher, _) =
    enemies.spawn(plain, 1, enemies.monster_freshness, rng.new(5))
  assert met.parts == fresher.parts
  assert enemies.freshness(enemies.grinder()) == 0
}

pub fn an_enemy_name_is_its_top_attribute_and_roster_name_test() {
  let e = enemies.scrap_gunner()
  let assert [buckler, buckler2, gun, ..rest] = e.parts
  let gun = part.attach(gun, 4, attribute.broken())
  let e = enemies.Enemy(..e, parts: [buckler, buckler2, gun, ..rest])
  assert enemies.name(e) == "Broken scrap gunner"
  let #(fly, _) = enemies.spawn(enemies.junk_fly(), 1, 0, rng.new(3))
  assert fly.name == "Damaged junk fly"
}

pub fn armor_and_batteries_have_their_own_words_test() {
  let plating = part.with(components.plating(), part.overclocked())
  assert part.display_name(plating) == "Reinforced plating"
  let dented = part.attach(components.plating(), 0, attribute.damaged())
  assert part.display_name(dented) == "Dented plating"
  let assert [block] = part.cards(dented)
  assert block.name == "Dented Block"
  // No word for Precise on armor: it doesn't go on.
  assert part.attach(components.plating(), 0, attribute.precise())
    == components.plating()
  let battery = part.with(components.battery(), part.overclocked())
  assert part.display_name(battery) == "High-capacity battery"
}

pub fn attributes_scale_a_growing_cards_growth_test() {
  // A Broken Compress grows to a fifth of a sound one, at a fifth the speed.
  let broken = attribute.apply(attribute.broken(), cards.compress())
  let assert Ok(#(per_second, cap)) = card.growth(broken)
  assert float.loosely_equals(per_second, 0.022, 0.0001)
  assert float.loosely_equals(cap, 1.0, 0.0001)
}
