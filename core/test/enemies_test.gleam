import gleam/list
import robots/content/enemies

pub fn every_enemy_is_a_legal_build_test() {
  // `robot` asserts the build is legal.
  list.each(enemies.levels(), fn(l) {
    list.each([l.boss, ..list.append(l.enemies, l.strong)], fn(e) {
      let bot = enemies.robot(e)
      assert bot.name == e.name
    })
  })
}

pub fn enemy_names_are_unique_per_build_test() {
  // A name always means the same build.
  let all =
    enemies.levels()
    |> list.flat_map(fn(l) { [l.boss, ..list.append(l.enemies, l.strong)] })
  list.each(all, fn(a) {
    assert list.all(all, fn(b) { a.name != b.name || a == b })
  })
}

pub fn levels_past_the_last_use_the_last_roster_test() {
  let assert Ok(last) = list.last(enemies.levels())
  assert enemies.level(9) == last
}
