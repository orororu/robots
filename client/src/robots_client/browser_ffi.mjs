// The only impure code in the game: the clock, timers and keyboard.

export function now() {
  // Monotonic: unaffected by the system clock being changed mid-match.
  return Math.floor(performance.now());
}

export function randomSeed() {
  return Math.floor(Math.random() * 2 ** 31);
}

export function every(ms, callback) {
  setInterval(() => callback(), ms);
}

export function onKeydown(callback) {
  document.addEventListener("keydown", (event) => {
    if (event.repeat) return;
    callback(event.key);
  });
}
