# Prismarine v23, Stage 1: Kernel core

**Status: written but never run.** There was no Lua interpreter available when this
was written, so it has only passed a block-balance check (every `function/if/do/repeat`
has its `end`/`until`). Expect to find bugs. The point of this stage is to find them
before the UI is built on top.

## What is in stage 1
- Process table: one coroutine and one hidden 51x18 window per app
- Event router: the kernel is the only reader of the real event queue
- App classes: `app` (max 6, foreground or frozen) and `service` (always runs, auto-restarts with growing delay, outside the cap)
- Frozen apps buffer their own timer / HTTP events and replay them on focus
- Crash handling: a dead app never takes the OS down; crashed apps wait for restart/dismiss
- Graceful stop (`terminate` event, 3 s grace) then force-kill; leftover files and timers are cleaned up
- Sandbox: whitelist environment, wrapped `fs` (hides kernel + settings files), no raw modem access, no `getfenv/setfenv/debug`
- Notification API stub (`prismarine.notify`), sanitized and rate-limited, apps cannot pose as "System"

Not in stage 1: top bar, menus, cabinet, animations, dashboard, toasts, Messenger/crypto.

## Install
Copy to the computer root so the paths match:

```
/kernel_test.lua
/prismarine/kernel/kernel.lua
/prismarine/kernel/sandbox.lua
/prismarine/tests/counter.lua  crasher.lua  spinner.lua  svc.lua  probe.lua
```

Run `kernel_test`. Dev keys (temporary, stage 2 replaces them):
F1 counter, F2 spinner, F3 crasher, F4 stop focused, F5 next app, F6 home,
F7 service, F8 sandbox probe, F9 restart/dismiss, F12 quit.
Ctrl+T is deliberately ignored while the kernel runs.

## Test checklist (please report what you actually see)
1. **F8 probe**: every line should say PASS. Any FAIL is a sandbox hole.
2. **F1 counter, F6 home, F5 back**: it should resume. After switching back it advances by 1, not by the seconds you were away (frozen means time stops).
3. **F3 crasher**: after 2 s the top row marks it `!` with the error text. F9 restarts it (or dismisses it if it already runs).
4. **F7 service, F6 home**: after ~8 s it crashes and the top row shows a restart countdown. Delay should grow: 2 s, 4 s, 8 s...
5. **F1 seven times**: the 7th is refused with "App limit reached (6)".
6. **F4 on a counter**: it closes cleanly.
7. **F2 spinner (the important one)**: note exactly what happens after the tight loop starts.
   - Best case: the app is marked crashed, the top row keeps working.
   - Worst case: the whole computer shuts down or freezes. If so, "Messenger never freezes" needs a different design.
8. **Ctrl+T** does nothing; **F12** returns to the shell.

## Known gaps and limits
- `require`, `shell`, `rednet`, `gps`, `os.run`, `os.shutdown`, `getfenv/setfenv`, `debug` are not available to apps. Old apps that use them will fail until the kernel provides replacements.
- Libraries that call the real `sleep` (e.g. `textutils.slowPrint`) can miss their wake-up if the app is frozen at that moment.
- Wired-modem remote peripherals are not filtered, only local modems.
- Handle cleanup on stop assumes `fs.open` handles can be closed by `h.close()`; untested.
- `K.snapshot` (cabinet previews) needs `window.getLine`; if missing it returns nil.
- The protected path list lives at the top of `sandbox.lua`. Check it matches where v23 keeps its secrets.
