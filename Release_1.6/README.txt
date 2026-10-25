VERSION RULE
  Every change to any file raises the version number. 1.0 becomes 1.1, then 1.2,
  and so on. No change ships under the same number. The number is the "version"
  line in manifest.txt, and the OS shows it as "Release <number>".
  After any change, run:  python3 tools/make_manifest.py   (it adds 0.1 for you)
  then:                   python3 tools/sign_manifest.py release.key
  Upload every changed file together with manifest.txt and manifest.sig.

Prismarine Release 1.5

Install
  Upload the contents of this folder to release in your GitHub repo.
  In game run: wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/release/setup.lua
  Keep the music file at the repo root.

What is new in 1.5
  Rooms
    New "rooms" permission and capability. The Rooms app (in the store) uses it for
    chat between players. The app asks once (Allow once, Always, No); Settings >
    Permissions can change it later. The OS carries the packets and does the
    cryptography; the app never sees a secret key.
    Every Rooms packet is signed with the computer's key and checked on arrival, so
    nobody can post under another key. Old and repeated packets are dropped. Only
    computers the app asked about are heard, with limits per sender and for the
    signature checks. Direct messages and room passwords are sealed boxes that only
    the receiving computer can open.
    Rooms is off on an Archive network and in Bunker mode (the Archive could not
    read it there). Rooms messages are not logged by the Archive.
  Pixel Dash
    New app in the store (programs/pixeldash.lua). Design a dashboard in the editor
    (panel, text, button, toggle, lamp, bar, clock; drag to move, drag the corner to
    resize, colors, borders, effects, undo), then run it on a monitor. Touching a
    button or toggle switches a redstone output; lamps and bars show a redstone
    signal. It asks once for monitor touch and keeps running in the background when
    allowed. Redstone output asks the first time it is used.
  Store
    Rooms and Pixel Dash are added to the store.

What is new in 1.4
  Updater
    The updater picks the release by folder. If the saved address points into a Release_X.Y
    folder, it asks the repo which Release_X.Y folders exist and uses the highest number
    (1.10 counts above 1.9). A new Release_1.5 folder is found with no change on the computer.
    If GitHub does not answer, the saved folder is used. The signature check and the
    refusal of older releases still apply to whatever folder it picks.

What is new in 1.3
  Fixes
    Archive mode no longer blocks the built-in apps from loading the UI kit. Starting
    an app on a Bunker computer crashed with "Not approved by the Archive". The built-in
    apps, the UI folder and the library folder may now be loaded; user programs still
    need an approval. The block message now names the file.
  Safety
    A power cut while a key file or an update is being saved no longer loses it. The next
    start finishes the move.
    The Archive log reports a failed write and a pulled disk no longer raises an error.
    A fault in the network timer is noted and the desktop keeps running.
    Junk or unreadable sealed messages from outside no longer write a record each. The
    Archive logs one summary line a minute, so they cannot fill its disk.

  Archive and network
    Flood limits. One sender, all senders together, and the slow signature checks each have
    a budget. A flood is counted, not logged line by line.
    Messages to the Archive are sent again until the Archive confirms them. The Archive logs
    each message once and confirms it every time it is sent again. If no confirmation comes,
    the member shows an alert.
    A request that would replace an existing member (same id, new key), come from a banned
    id or key, or reuse a name is flagged. The Archive owner must confirm it a second time.
    A ban covers the key as well as the id. Two members with one name show with their ids.
    The Archive refuses oversized requests, caps program reviews (20 total, 5 per member),
    caps files collected at once (8), drops files that stall and logs that they were lost.
    The Archive hashes program code itself. The hash a member claims is ignored.
    A member the Archive has not heard from for 5 minutes is logged as silent.
    A member that has not heard from the Archive for 6 hours trusts only the Archive until
    it answers. Settings > Network shows how old the roster is.
    A program the Archive stops approving is stopped on every member.
    Joining shows a warning that the Archive reads everything, and the person types the first
    group of the Archive key before joining.
    The Archive owner's own messages, posts and file offers are logged.
    Lost Archive: the Archive makes a dissolve token when it is created (Archive app, Info
    tab, asks the password). Any member can leave with it in Settings > Network.
    Forgot password on an Archive: the reset needs the words ERASE ARCHIVE and says the logs
    are lost for good.
    Deleting a day of logs asks the password and leaves its own record.
    A log write that fails is kept in memory (up to 500 records), tried again, and raises an alert.
  Passwords
    New passwords need 8 characters and use 20000 rounds. Older passwords keep working.
    Becoming an Archive needs a password made under the new rules.
  Updates
    The update list must be signed (manifest.sig, made by tools/sign_manifest.py). To accept
    unsigned lists on a private server, set REQUIRE_SIGNATURE to false at the top of
    prismarine/sys/update.lua. A list older than the installed release is refused.
    An installed Archive app updates with the release and is checked against its hash.
    An update writes a sealed journal first. After a power cut the next start finishes it.
  Background apps
    Settings > Background chooses which apps keep running when they are not in front.
    The Archive app keeps running by default. Audio asks once for permission to run in the
    background, on top of what it already asks.
  Themes
    Settings > Themes saves the colors on screen as a theme, installs a theme from an https
    link, and removes your own. Theme files live in /prismarine/themes as JSON:
      { "name": "Midnight", "author": "Alex", "logoColor": "Violet",
        "colors": { "hdr": "purple", "line": "magenta", "sel": "pink", "selText": "black" } }
    Colors use the CC color names (white, orange, magenta, lightBlue, yellow, lime, pink, gray,
    lightGray, cyan, purple, blue, brown, green, red, black). Roles you leave out keep the
    Ocean look. A theme holds colors only, never code. Files over 4 KB are ignored.
    Audio 5 follows every built-in and custom theme. If a theme makes text or bars hard to
    see, Audio picks a readable color for them.
  Audio 5
    Taller and more sensitive visualizers, a Float mode, a better empty list, a speaker
    pop-up (key O), and background permission. It draws with Pixelbox when the OS offers it.

What is new in 1.1
  Disks
    Select many files: Ctrl+click adds or removes one, Shift+click picks a range.
    From the keyboard: Space marks the row, Shift+Up/Down extends, Ctrl+Up/Down moves without
    changing the marks, Ctrl+A picks all, Esc clears. The mouse wheel keeps the marks.
    Copy (C), Cut (X), Paste (P) and Delete (D) work on every marked item. Ctrl+C, Ctrl+X, Ctrl+V work too.
    Cut items show a "cut" tag until you paste them. Paste skips names that already exist and a
    folder pasted into itself, says how many, and still pastes the rest. Cut works between drives.
    ROM items cannot be cut.
  One copy of each program
    A program opens once. Opening it again switches to the open one instead of starting a second
    (two Downloads, two Settings and so on). This holds for the Apps menu, the Programs app and
    programs that start other programs. A program that crashed starts fresh when opened again.
    An open program still opens at the app limit. New args are ignored when it is already open.

What is new in 1.0
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

  New look in 24.3
    Every built-in app now uses pixel cards: rounded panels, key chips, status badges, meters and switches.
    Programs: list and detail card with hash and Run button.
    Disks: volume cards with a usage meter.
    Download: one card list with Get, Update and Installed badges.
    Vault: list with a preview card. Locked screen and password maker redone.
    Messenger: chat bubbles, input pill, pairing buttons.
    Settings: sidebar card, switches, value pickers.
    Others and Archive: tabs as pills, content on cards.
    Editor: current line highlight and a status bar with a language chip.
    Shell: Shell v2 is now the built-in Shell. It runs on a full shell API, with history, aliases,
    chaining, Tab completion and settings. Its boot screen, self update and palette changes are off.
    Apps use /prismarine/ui/kit.lua: kit.scene() gives s:card, s:pill, s:badge, s:meter, s:switch,
    s:row, s:field, s:hints, s:header and s:flush.

Fixes in 24.2
  New frame buffer: the OS and every app draw into one buffer, and only changed cells reach the screen.
  No half drawn frames, so menus, drawers and toasts no longer flicker. Redraws send 10 to 30 times less.
  Menus on the left wall have square corners on every side. Toasts on the left do too.
  Portals showed a black screen. Device calls that finish on the server thread never returned to the app.
  The kernel now delivers that answer to the app that waits for it. Portals also draws before it scans.
  Every built-in app has one look: title chip, key hints that fit, selection marker, scroll bar,
  empty page text, themed colors. Footers no longer cut off in the middle of a word.
  New file prismarine/ui/screen.lua (frame buffer) and prismarine/ui/kit.lua (app look).

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
