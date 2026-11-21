import gleam/int
import gleam/list
import robots/rng

pub fn same_seed_same_sequence_test() {
  let #(a, _) = rng.next(rng.new(42))
  let #(b, _) = rng.next(rng.new(42))
  assert a == b
}

pub fn known_value_is_stable_across_targets_test() {
  // Pinning a value guards against the Erlang and JS targets diverging.
  let #(a, seed) = rng.next(rng.new(1))
  let #(b, _) = rng.next(seed)
  assert a == 96_542
  assert b == 365_211_588
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
