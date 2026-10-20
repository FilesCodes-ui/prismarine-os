Prismarine v24.0 stage 6

Install
  Upload the contents of this folder to stage6 in your GitHub repo.
  In game run: wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage6/setup.lua
  Keep the music file at the repo root.

What is new
  Permissions
    Safe apps run free. Some actions ask first: web, redstone output, other devices, files outside the app's own folder, shared redstone inputs, monitor touch.
    The card gives three choices: Allow once, Always, No. Keys 1, 2, 3.
    Always is saved and tied to the app file hash. A changed file asks again.
    Settings, Permissions page: set Ask, Always or Never per app.
    Bunker refuses every ask.
  Shared redstone inputs
    One list that apps share. Modes: button, toggle, hold. Threshold, invert, debounce.
  Theme API
    One line in an app: local T = prismarine and prismarine.theme or require("prismarine_theme_fallback")
    Read only. Apps get a notice when the theme changes, at most once per second.
  Themes
    12 themes. More recolorable roles. Live themes: Day and night, Drift, Seasons, Alert tint.
  Screen saver
    Tide, Starfield, Clock, Logo drift. Off by default. Any input wakes it.
  Download app
    Official tab: signed list, every file checked against a pinned hash.
    Custom link tab: any https address, 18 MB limit.
  Archive
    Installs from Settings as an add-on with a pinned hash.
    Keep free options: 1, 5, 10 MB.
  Signed releases
    manifest.sig is checked with the key built into sys/update.lua.
    A wrong signature is always refused. A missing one is allowed with a note, refused in lockdown.

Store folder
  store/store.json lists the official downloads. Audio v3 is in store/p.audio_v3.lua.
  Living Mice points to the music file at the repo root.

Not included
  Shell v2 needs the real shell global and runs only in Classic.
  Dash and Switchboard are separate downloads, coming later.

Never upload the release private key.
