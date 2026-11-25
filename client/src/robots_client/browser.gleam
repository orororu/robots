@external(javascript, "./browser_ffi.mjs", "now")
pub fn now() -> Int

@external(javascript, "./browser_ffi.mjs", "randomSeed")
pub fn random_seed() -> Int

@external(javascript, "./browser_ffi.mjs", "every")
pub fn every(ms: Int, callback: fn() -> Nil) -> Nil

@external(javascript, "./browser_ffi.mjs", "onKeydown")
pub fn on_keydown(callback: fn(String) -> Nil) -> Nil

/// The saved profile's text, or "" if there is none.
@external(javascript, "./browser_ffi.mjs", "loadProfile")
pub fn load_profile() -> String

@external(javascript, "./browser_ffi.mjs", "saveProfile")
pub fn save_profile(text: String) -> Nil
