PRISMARINE STAGE 4 (visuals)

Install:
wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage4/setup.lua
Then reboot.

Upload the stage4 folder to GitHub (main branch) first.

What to check:
1. Boot: the logo fades in, a bar fills, then Home shows with a clock and hint.
2. Home has a faint blue glow that fades to black at the top and bottom.
3. Click the badge at the top right, or press F8, to open the notifications sidebar.
4. Drag the slider or use the mouse wheel to scroll. Click an entry to open its app.
5. Click [Clear] to empty the list. Backspace or a click outside closes it.
6. Apps rise from the bottom and sink on close. Menus slide in and out.
7. [H] on the top bar goes Home.
8. Settings: Haze, Logo color, Animations, Notifications.

Theme file: /prismarine/data/theme.json
Keys: colors by role, logoColor, animations, fps (2 to 30).
Logo colors: Blue, Prismarine, Aqua, Emerald, Lime, Gold, Orange, Red, Rose, Magenta, Violet, Ice, Rainbow, or #RRGGBB.

Load screen: ui_test.lua now shows the logo and a progress bar first, then loads the kernel and the interface behind it.

Settings app: open it from the Apps menu.
Pages: Display (animations, haze, frame rate, logo color), Alerts (do not disturb, toast side, message text, test toast, clear list), Controls (key and mouse reference), System (version, graphics, screen, reset).
Mouse: click a page, click a row, click < or > to change a value.
Keys: Up/Down, Left/Right, Enter or Space, Tab or PageUp/PageDown, q.
Apps reach settings through prismarine.ui (get, set, reset).

Themes: Settings > Display > Theme. Ocean, Ember, Forest, Orchid, Gold, Mono. A theme sets bar, menu and toast colors plus the logo color.
Home shows app and alert counts above the clock. Toasts carry an icon: i info, ! warn, x error.
