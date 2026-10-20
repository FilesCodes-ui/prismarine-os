PRISMARINE v23 STAGE 3

WHAT CHANGED
Pixelbox_lite draws the menus, toasts, crash card and dashboard.
Every panel has a thin outline. Menus and the switcher slide in.
The dashboard shows the exact v21 PRISMARINE logo.
It uses the v21 smooth shade palette, the shine on the gray half,
the water ripple on the colored half and the rising bubbles.
The computer now starts Prismarine on boot.

INSTALL
1. Drag the stage3 folder onto the GitHub Upload page. Commit.
2. On the computer run:
   wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage3/setup.lua
3. Reboot. Prismarine starts by itself.

Setup needs HTTP, the same as the rest of Prismarine.
It downloads Pixelbox from a pinned commit and checks its SHA-256.
A bad or missing Pixelbox means plain text mode. A toast tells you why.

COLORS
The dashboard changes the palette while you are on Home.
Apps get the normal palette back as soon as one has focus.

SKIP BOOT
Hold R in the first second after power on. You get the normal shell.
Delete /startup.lua to stop booting into Prismarine.
Your old startup.lua is saved as startup.lua.bak.

WHAT TO CHECK
1. Boot: the logo shows with a sweeping shine, a rippling blue half and bubbles.
2. Left Alt: the menu slides in from the left with an outline.
3. Right Alt: the switcher slides down from the bar.
4. Run Toaster, press 1 to 5, go Home. Toasts have outlines.
5. Run Crasher. The card has a red outline.
6. Go into an app. The colors look normal. Go Home. The logo colors return.
7. Apps, More, Animations: off. The logo holds still.
8. Power off, power on. You land on the dashboard.

CUSTOMIZE
/prismarine/data/theme.json appears after the first run.
Change any color name there. Set animations to false. Set fps from 2 to 30.
logoColor takes Blue, Prismarine, Aqua, Emerald, Lime, Gold, Orange, Red,
Rose, Magenta, Violet, Ice, Rainbow or any #RRGGBB.
Run: edit /prismarine/data/theme.json
