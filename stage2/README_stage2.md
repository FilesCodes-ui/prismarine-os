# Prismarine v23, stage 2: top bar, menus, switcher, toasts

Run `ui_test`. Click the top bar with the mouse.

Top bar
- `[= Apps]` opens the App Manager. Start programs, switch to or stop running ones.
- `[v Active: name]` opens the filing-cabinet switcher with a preview.
- `[H]` goes Home. The clock and a badge show on the right. `*3` means 3 unread notifications.

Keys: Left Alt = App Manager, Right Alt = switcher, Up/Down/Enter in menus,
Backspace closes a menu, F12 quits.

Not yet: Pixelbox animations, real dashboard, Messenger, crypto.

Test checklist
1. Apps menu: start Counter. Open Apps again and start more apps until Counter shows (full).
2. Switcher: click a tab to select, click it again to open. Check the preview.
3. Toaster: it is a background service. Start it, open it from RUNNING, press 1 to 5, then press [H] or open another app. A toast slides in after 4 seconds. A toast for the app you are viewing is hidden.
4. Crasher: a crash card shows with [Restart] and [Close]. R and C work too.
5. Apps > More...: toggle toast side, Do not disturb, Show message text. Open Notification history.
6. Stop apps with [Stop] in RUNNING.
