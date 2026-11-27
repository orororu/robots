// The only impure code in the game: the clock, timers, keyboard and the
// saved profile.

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

// The player's profile (Salvage, blueprints, designs), kept in the browser.
// Storage can be unavailable (private windows, blocked site data): then
// nothing is kept between visits.
const profileKey = "robots.profile";

export function loadProfile() {
  try {
    return window.localStorage.getItem(profileKey) || "";
  } catch {
    return "";
  }
}

export function saveProfile(text) {
  try {
    window.localStorage.setItem(profileKey, text);
  } catch {
    // Not kept: storage is unavailable.
  }
}

// The run in progress, so a reload continues it. "" removes it.
const runKey = "robots.run";

export function loadRun() {
  try {
    return window.localStorage.getItem(runKey) || "";
  } catch {
    return "";
  }
}

export function saveRun(text) {
  try {
    if (text === "") window.localStorage.removeItem(runKey);
    else window.localStorage.setItem(runKey, text);
  } catch {
    // Not kept: storage is unavailable.
  }
}
