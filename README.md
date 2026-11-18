<p align="center">
  <img src="assets/banner.svg" alt="CaffeineOSS — caffeinate your mac" width="100%">
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-1b1207?style=flat-square&logo=apple">
  <img alt="language" src="https://img.shields.io/badge/Swift-6-ff9f43?style=flat-square&logo=swift&logoColor=white">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-0-2c1c0d?style=flat-square">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-e9b878?style=flat-square">
</p>

<h3 align="center">A tiny menu-bar app that keeps your Mac awake — even with the lid closed. ☕</h3>

## Use

- **Click** the cup to toggle. **Right-click** for timers (15 min – 8 h) and options.
- Outline cup = sleep allowed. Filled cup = awake; the menu shows until when.
- **Stay Awake with Lid Closed** (on by default) keeps it running with the lid shut — handy for leaving `claude` working overnight. The screen turns off while the lid is closed.
- **Open at Login** is one checkbox.

## Install

Download the zip from [Releases](https://github.com/karimbacchus/caffeineOSS/releases) (signed and notarized), unzip, and move it to Applications.

Or build it yourself (needs `xcode-select --install`):

```bash
git clone https://github.com/karimbacchus/caffeineOSS.git && cd caffeineOSS
./build.sh && open CaffeineOSS.app
```

`build.sh` signs with your Developer ID if you have one, otherwise ad-hoc. `./build.sh --zip` makes a release zip; add `NOTARY_PROFILE=<profile>` to notarize it.

## How it works

It does what you'd type by hand, using Apple's own mechanisms:

| | |
|---|---|
| `caffeinate -dims` | Held as IOKit power assertions inside the app, so macOS releases them automatically if it quits or crashes. |
| `sudo pmset -a disablesleep 1` | The only way to stop lid-close sleep. Needs root: the first time you get one password prompt, which installs `/etc/sudoers.d/caffeineoss` allowing *only* `pmset -a disablesleep 0\|1`. After that, no prompts. |

Everything is undone when you toggle off, a timer ends, or you quit — and on next launch if the app was force-killed.

## What's new in 2.0

**Fixes**
- Lid-closed mode no longer leaves the Mac unable to sleep after a crash or force-quit.
- No more orphaned `caffeinate` process when the app is killed.
- No password prompt on every toggle — just once, ever.
- Display now turns off while the lid is closed instead of staying lit (left on with an external monitor).
- Clicking the cup now actually toggles it.

**New**
- Menu with live status, timers, lid-closed option and Open at Login.
- Liquid Glass–ready: native menus and SF Symbols, plus a glass-style app icon.
- Universal binary (Apple silicon + Intel), Swift 6, Developer ID signed and notarized.

## Uninstall

Untick **Open at Login**, quit, then:

```bash
rm -rf /Applications/CaffeineOSS.app
sudo rm -f /etc/sudoers.d/caffeineoss
```

## Why it exists

A work MDM blocked KeepingYouAwake, Caffeine, and even LaunchAgents — but not an app you compile yourself. So the original author ([kuberwastaken](https://github.com/kuberwastaken/caffeineOSS)) wrote one in a single Swift file. This fork polishes it up. No-install fallback: `caffeinate -d` in Terminal.

MIT licensed — see [LICENSE](LICENSE).
