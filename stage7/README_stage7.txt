Prismarine v24.0 stage 7

Install
  Upload the contents of this folder to stage7 in your GitHub repo.
  In game run: wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage7/setup.lua
  Keep the music file at the repo root.

What is new
  Screen saver
    Tide fills the whole screen with waves. PRISMARINE sits in the middle and the holes in the letters show the waves.
    The saver covers the lock screen. Waking a locked computer asks for the password. An unlocked one goes to Home.
    Settings, Saver page: start time, style, show name, preview.
  Palettes
    The logo color changes only the logo. The top bar, menus and toasts keep their colors.
    Logo color and saver color each have presets and a Custom mixer (Red, Green, Blue).
    Follow logo color: the saver uses the logo color until you turn it off.
  Settings
    New pages: Look, Home, Saver, Clock, Alerts, Security, App access, Network, Keys, Colors, System.
    Every page has a one line intro. Every row has a plain help line.
  Readability
    Text on any color you pick turns black or white when it would be hard to read.
  Password check and lock screen
    The check works in short slices, so the screen stays smooth. A real progress bar shows while it runs.
  Home
    The key hint line scrolls when it is wider than the screen.
    The glow behind the logo is back.
  Messenger
    Find people is F10. It scans on its own and says when no modem is found.
  Alerts
    Toasts always slide in, even when the sender is the focused app.
    A toast warns at boot when the computer holds under 5 MB.
  Others
    New Guides page: how to raise the computer space limit.
  Installer
    setup.lua stops early with steps when a fresh install has too little room.
  Apps
    A program header may sit up to 20 lines down, below the banner.

Built-in apps (new in 24.1)
  Editor
    Edit text, Lua and JSON files. Colors follow the code as you type.
    Make new files and folders from the Open window (Ctrl+O, then N or M) or with Ctrl+N.
    Select with Shift and the arrows. Copy, cut, paste, undo, redo, find, go to line.
    Saving a Lua file checks it and shows the line of any mistake. JSON gets checked too.
    Files up to 300 KB. Hidden while Bunker mode is on.
  Vault
    A short list of logins, keys and notes, sealed with a key made from your password.
    It asks for the password every time it opens and locks itself after 90 quiet seconds.
    The secret stays hidden until you press S, and hides again after 10 seconds.
    The password maker uses strong random bytes. F2 inside an item fills the secret.
    A password change re-seals the Vault. With no password set, items are only hidden.

Fixes in 24.1
  Download app: no flicker and far less lag. The list is checked once, not on every redraw.
  Menu and toast edges no longer show a colored bar in the screen margin.
  The Apps tab keeps its color. Logo drift is gone from the Saver styles.
Downloads
  Portals: open, seal, hold open, and name Egress portals from a computer that touches a frame block.
  It asks once to allow devices. Get it from the Download app, Official files.
Downloads, coming next
  Shell v2, Dash, Rooms, Switchboard, remote control and turtle tools.
  They come from the Download app, not the release.
