PRISMARINE OS v23, STAGE 5

INSTALL
1. Upload the stage5 folder to your repo, next to the older stages.
2. On the computer, run:
   wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage5/setup.lua
3. The computer reboots into Prismarine. Choose a password, or press N for none.

Prismarine replaces the CraftOS shell. The computer boots straight into it.
Your old startup file is saved as startup.lua.bak.

WHAT TO CHECK
1. Setup. Pick a password. Reboot. Log in. Try a wrong password five times.
   Or press N at setup for no password. Turn one on later in Others.
2. Lock. Press F9. The screen locks. Your password opens it.
3. Home. The logo keeps its place. The haze sits behind it.
4. Settings. Open every page. Change the theme, colors, clock, toast time.
   Turn Rounded corners off and on.
5. Messenger. Put a modem on two computers. Find people with F2. Pair them.
   Compare the codes. Send a message. Send a file with F3.
6. Archive. On one computer open Settings, Network, Make this computer an
   Archive. On the others choose Find Archives, then Join. The Archive app
   approves them.
7. Archive mode. After joining, the Shell is locked. New programs only run
   after the Archive approves their exact hash. The Programs app asks for it.
8. Bunker. The Archive computer locks itself harder. Open the Archive app.
   Try Find, then open a day. M marks a line. P prints. E saves plain text.
   Print and save ask for your password. The Disks tab sets where logs go.
9. Update. Others, Update page. A check runs at every boot. You install it.

KEYS
Left Alt     Apps menu
Right Alt    Switch apps
F8           Notification sidebar
F9           Lock
Tab          Next page in Settings and Others

SECURITY
Your password makes a key with PBKDF2 and 10000 rounds. The key seals your
identity keys on disk. A copied disk gives nothing without the password.
Five wrong passwords start a lockout. It grows to one hour.
Every boot hashes each system file and compares the hashes with a sealed list.
A changed file shows a warning before the desktop starts.
Messages are signed with Ed25519 and encrypted with ChaCha20-Poly1305.
Each message has a counter and a time, so a replay is dropped.
Each sender is limited to a small burst of messages.
The Archive signs who belongs to the network. A banned computer is ignored.
There is no remote wipe.
In an Archive network the Archive reads every message in full. Logs on its
disk are encrypted with a key only it holds.
Apps never see keys. They get narrow functions and nothing else.

OPTIONAL PASSWORD
No password means a random key on this computer seals your secrets. It stops
casual reading. Anyone who holds the disk reads the key. Lock and F9 do not
exist without a password. Turn a password on or off in Others, Password page.
An Archive computer always needs a password. Turning it off is refused there.
A computer that holds Archive files asks for a password at boot.

ARCHIVE MODE LOCKS
Shell and raw Lua, new and edited programs, disk writes, and settings that
weaken security (auto-lock off or above 15 minutes).

BUNKER MODE
Any computer that holds the Archive turns it on by itself. It also hides
Programs, Download and Disks, and refuses to join another Archive. Auto-lock
stays at 5 minutes or less. The status bar shows Bunker.

ARCHIVE STORAGE
Logs stay encrypted on every disk. Modes: computer, overflow (disks when space
runs low), disks, mirror. The Archive app copies logs to a disk on request.
Print and plain text export need your password. Each one adds a line to the log.

LIMITS
Someone with hands on the computer or a disk drive reaches the files. The
password and the sealed keys protect your data and messages, not the machine.
The crypto was tested in an emulator, not in the real game. Report any error.
Update files come over HTTPS from GitHub and are hash checked against the
release list. The list itself is not signed yet.

REPORT BACK
1. Any error text on screen.
2. Whether password setup and login take long. Tell me the seconds.
3. How the rounded corners look on your screen.
4. Whether pairing, messages and files work between two real computers.

CREDITS
ccryptolib by Miguel Oliveira, MIT. Pixelbox Lite by 9551-Dev, MIT.
