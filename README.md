<p align="center">
  <img src="assets/banner.svg" alt="CaffeineOSS — caffeinate your mac" width="100%">
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-1b1207?style=flat-square&logo=apple">
  <img alt="language" src="https://img.shields.io/badge/Swift-6-ff9f43?style=flat-square&logo=swift&logoColor=white">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-0-2c1c0d?style=flat-square">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-e9b878?style=flat-square">
  <img alt="kexts" src="https://img.shields.io/badge/kernel%20extensions-none-3b2410?style=flat-square">
</p>

<h3 align="center">A tiny menu-bar app that stops your Mac from falling asleep. One click. Filled cup = awake. ☕</h3>

---

## The story (or: why this exists at all)

I wanted the classic coffee-cup-in-the-menu-bar thing. Easy, right? Except my **work laptop's MDM** had other plans:

1. Tried [**KeepingYouAwake**](https://github.com/newmarcel/KeepingYouAwake) → blocked.
2. Tried the classic **Caffeine** app → blocked.
3. Tried dropping a **LaunchAgent** → turns out the MDM had made `~/Library/LaunchAgents` *root-owned*. Blocked.

At that point it was personal. Downloaded apps get a quarantine flag and have to clear notarization + an endpoint-management allowlist — but a binary **you compile locally** has no quarantine flag and isn't a pre-built app the MDM recognizes. So I got bored, opened a `.swift` file, and wrote my own in ~120 lines.

**CaffeineOSS wasn't a real project.** It's not on Homebrew, it wasn't on GitHub, the name didn't exist. I just built it because I was bored and the corporate firewall made me angry. Now it's here. ☕

---

## What it actually does

When you flip it on, CaffeineOSS does exactly what you'd type by hand — nothing exotic, just Apple's own tools:

```bash
caffeinate -dimsu              # prevent display / idle / disk / system sleep + keep "user active"
sudo pmset -a disablesleep 1   # also stop the forced sleep that happens when you CLOSE THE LID
```

- It holds the same IOKit power assertions as `caffeinate -dims`, **in-process** — so if the app quits or crashes, macOS drops them automatically. No orphaned helper processes.
- If **Stay Awake with Lid Closed** is on (default), it also flips `pmset disablesleep` so the Mac **stays awake even with the lid shut** (great for leaving `claude` running overnight). That part needs root, so the **first** time you get one native admin prompt (Touch ID or password). It installs `/etc/sudoers.d/caffeineoss`, which lets your account run exactly `pmset -a disablesleep 0|1` and nothing else, so every toggle after that is silent. Or turn the option off in the menu if you never close the lid.
- While the lid is shut, the display is allowed to turn off (no point lighting a closed screen); it comes straight back when you open the lid. With an external monitor connected (clamshell mode), displays are kept awake as usual.

Everything is undone the moment you toggle off, when a timer expires, or when you quit. And if the app was ever force-killed while lid-sleep was disabled, it restores normal sleep on the next launch.

> [!NOTE]
> The first cut of this app only held a single `PreventUserIdleDisplaySleep` IOKit assertion (== `caffeinate -d`). That keeps the screen on while the lid is **open**, but the Mac still sleeps the instant you close the lid. `disablesleep` is the only thing that defeats clamshell sleep — which is why the lid-closed case now works.

- 🖱 **Click** the cup to toggle. **Right-click** (or ⌃-click) for the menu.
- 🟤 **Outline cup** = sleep allowed (normal)
- ☕ **Filled cup** = staying awake — the menu shows *until when* and whether lid-close is covered
- ⏱ **Timed modes** — 15 min / 30 min / 1 h / 2 h / 5 h / 8 h, then auto-off
- 🚀 **Open at Login** — one checkbox (uses the modern `SMAppService` login item)
- 🪟 **Liquid Glass ready** — native `NSMenu` + SF Symbols adopt the macOS 26/27 glass look automatically; glass-style app icon included
- 🪶 **Featherweight** — one Swift file, zero dependencies, no Dock icon, universal binary (Apple silicon + Intel)

---

## Install

**Download:** grab `CaffeineOSS-<version>.zip` from [Releases](https://github.com/karimbacchus/caffeineOSS/releases), unzip, move `CaffeineOSS.app` to `/Applications`, open it.

### …or build it yourself (that's the whole point)

You need the Xcode Command Line Tools (`xcode-select --install`). Then:

```bash
git clone https://github.com/karimbacchus/caffeineOSS.git
cd caffeineOSS
./build.sh
open CaffeineOSS.app
```

`build.sh` compiles `main.swift` as a universal binary, wraps it in a proper `.app` bundle, and signs it — with your **Developer ID** (hardened runtime) if one is in your keychain, otherwise **ad-hoc**. Either way a local build has no quarantine flag for an MDM/Gatekeeper to choke on. `./build.sh --zip` also produces a release zip.

> [!TIP]
> Because you compiled it yourself, there's no `com.apple.quarantine` attribute and nothing for notarization gates to reject. This is exactly why it runs where the prebuilt apps didn't.

---

## Start at login (survives reboots)

Right-click the cup → **Open at Login**. That registers a standard login item (no `~/Library/LaunchAgents` needed, so it works even when an MDM has locked that directory down). You can also manage it in **System Settings → General → Login Items**.

---

## Uninstall

```bash
# untick "Open at Login" in the menu first, then:
osascript -e 'quit app "CaffeineOSS"'
rm -rf CaffeineOSS.app
sudo rm -f /etc/sudoers.d/caffeineoss   # the passwordless pmset rule, if installed
```

---

## No-install fallback

If even a locally-built app gets blocked, macOS ships the original. Zero install, zero app:

```bash
caffeinate -d        # keep display awake until Ctrl-C
caffeinate -t 3600   # awake for 1 hour
caffeinate make      # awake until `make` finishes
```

CaffeineOSS is really just a friendly coffee cup glued on top of that idea.

---

## Project layout

```
caffeineOSS/
├── main.swift              # the entire app (~200 lines)
├── build.sh                # compile (universal) → .app bundle → sign → optional zip
├── scripts/make-icon.swift # renders assets/AppIcon.icns
├── assets/
│   ├── AppIcon.icns        # glass-style app icon
│   └── banner.svg          # the cup up top
└── README.md
```

---

## License

MIT — see [LICENSE](LICENSE). Do whatever you want with it. ☕

<p align="center"><sub>Built because I was bored and the corporate firewall made me angry.</sub></p>
