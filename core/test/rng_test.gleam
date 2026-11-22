import gleam/int
import gleam/list
import robots/rules/rng

pub fn same_seed_same_sequence_test() {
  let #(a, _) = rng.next(rng.new(42))
  let #(b, _) = rng.next(rng.new(42))
  assert a == b
}

pub fn known_value_is_stable_across_targets_test() {
  // Pinning a value guards against the Erlang and JS targets diverging.
  let #(a, seed) = rng.next(rng.new(1))
  let #(b, _) = rng.next(seed)
  assert a == 493_207_134
  assert b == 597_854_672
}

pub fn shuffle_is_a_permutation_test() {
  let items = list.repeat(0, 20) |> list.index_map(fn(_, i) { i })
  let #(shuffled, _) = rng.shuffle(items, rng.new(7))
  assert shuffled != items
  assert list.sort(shuffled, int.compare) == items
}

pub fn int_below_stays_in_range_test() {
  let #(_, values) =
    list.map_fold(list.repeat(0, 200), rng.new(3), fn(seed, _) {
      let #(v, seed) = rng.int_below(seed, 6)
      #(seed, v)
    })
  assert list.all(values, fn(v) { v >= 0 && v < 6 })
}

/// Regression: small consecutive seeds (as the simulation uses) used to leave
/// the first item on top of the first shuffle 96% of the time.
pub fn first_shuffle_is_fair_for_small_seeds_test() {
  let items = list.repeat(0, 9) |> list.index_map(fn(_, i) { i })
  let on_top =
    list.repeat(0, 900)
    |> list.index_map(fn(_, seed) { rng.shuffle(items, rng.new(seed)).0 })
    |> list.count(fn(shuffled) { list.first(shuffled) == Ok(0) })
  // Fair is 1 in 9 = 100 of 900.
  assert on_top > 60 && on_top < 140
}

pub fn consecutive_seeds_are_not_in_lockstep_test() {
  // Seeds 1, 2, 3... used to give the same first `int_below(_, 3)`.
  let firsts =
    int.range(1, 31, [], list.prepend)
    |> list.map(fn(i) { rng.int_below(rng.new(i), 3).0 })
  assert list.contains(firsts, 0)
  assert list.contains(firsts, 1)
  assert list.contains(firsts, 2)
}
