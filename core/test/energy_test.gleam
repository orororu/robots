import robots/energy

pub fn accumulates_over_time_test() {
  let e = energy.new(0.0, rate: 1.0, cap: 10.0, now: 0)
  assert energy.at(e, 3500) == 3.5
}

pub fn caps_at_maximum_test() {
  let e = energy.new(2.0, rate: 1.0, cap: 10.0, now: 0)
  assert energy.at(e, 60_000) == 10.0
}

pub fn spend_rejects_when_short_test() {
  let e = energy.new(0.0, rate: 1.0, cap: 10.0, now: 0)
  assert energy.spend(e, 4.0, 3500) == Error(3.5)
}

pub fn spend_rebases_and_keeps_accumulating_test() {
  let e = energy.new(0.0, rate: 1.0, cap: 10.0, now: 0)
  let assert Ok(e) = energy.spend(e, 2.0, 5000)
  assert energy.at(e, 5000) == 3.0
  assert energy.at(e, 6000) == 4.0
}

pub fn stale_timestamp_grants_nothing_test() {
  let e = energy.new(0.0, rate: 1.0, cap: 10.0, now: 0)
  let assert Ok(e) = energy.spend(e, 1.0, 5000)
  // An action stamped "in the past" must not rewind the clock.
  let assert Ok(e) = energy.spend(e, 1.0, 1000)
  assert energy.at(e, 5000) == 3.0
}

pub fn set_rate_applies_from_now_on_test() {
  let e = energy.new(0.0, rate: 1.0, cap: 10.0, now: 0)
  let e = energy.set_rate(e, 2.0, 2000)
  assert energy.at(e, 3000) == 4.0
}
