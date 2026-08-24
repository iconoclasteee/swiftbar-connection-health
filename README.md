<div align="center">

# SwiftBar Connection Health

**A macOS menu bar indicator that answers one question at a glance: is my internet healthy, or should I switch to another Wi-Fi / cellular hotspot?**

Built around one constraint most menu bar tools ignore — the indicator occupies a **strictly constant width**, so it never shifts the icons sitting to its left.

![macOS](https://img.shields.io/badge/macOS-Ventura%2B-000000?logo=apple&logoColor=white)
![SwiftBar](https://img.shields.io/badge/SwiftBar-plugin-FF6A00)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-EN%20%2F%20FR-blue)
![tests](https://img.shields.io/badge/tests-built--in%20self--test-brightgreen)
![licence](https://img.shields.io/badge/licence-MIT-lightgrey)

**English** · [Français](README.fr.md)

</div>

---

## What it looks like

```text
┌─ menu bar ──────────────────────────────────────────────────────┐
│                       🟡 120ms              🔋  📶  🕐  You...  │
└─────────────────────────────────────────────────────────────────┘
                          └── coloured dot + latency, fixed width
```

The colour is the instant verdict, the number is the nuance:

| Display | Meaning | Threshold |
|---|---|---|
| 🟢 `42 ms` | healthy | < 80 ms |
| 🟡 `120ms` | good | 80 – 149 ms |
| 🟠 `200ms` | fair | 150 – 279 ms |
| 🔴 `400ms` | poor, but still connected | ≥ 280 ms |
| 🔴 `1834` | very poor — past 999 ms the unit is dropped, the value stays exact | ≥ 1000 ms |
| ⚫ `-OFF-` | no network at all → switch connection | probe failed / timed out |
| 🚫 `LOGIN` | captive portal → open a browser and sign in | response ≠ `204` |

The text is **always 5 characters wide**, rendered in a monospace font. `-OFF-` and `LOGIN` are intentionally left untranslated: they are language-neutral and must stay exactly 5 characters. The full wording lives in the dropdown.

---

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [The dropdown](#the-dropdown)
- [Language](#language)
- [Wi-Fi name helper](#wi-fi-name-helper)
- [Settings](#settings)
- [How it works](#how-it-works)
- [Tests](#tests)
- [Troubleshooting](#troubleshooting)
- [Repository layout](#repository-layout)
- [SwiftBar notes](#swiftbar-notes)
- [Contributing](#contributing)
- [Licence](#licence)

---

## Features

- **Guaranteed constant width** — 5 characters, monospace font, contract asserted by the built-in self-test. Neighbouring icons stop moving.
- **Tells the three ways of being cut off apart** — no network (⚫), captive portal (🚫), and "network + DNS fine but the web is silent".
- **Honest latency** — the TCP handshake RTT, not the total request time, which would inflate the figure 3-4×.
- **Breakdown only when needed** — the extra probes (raw IP without DNS, name resolution) run *only* when the main probe fails.
- **Bilingual** — every label in English or French, `UI_LANG` follows the system language by default.
- **Wi-Fi name despite the macOS lock** — through a 40-line signed helper, authorised once and for good.
- **Useful clickable rows** — gateway opens your router's admin page, the failure cause opens Wi-Fi settings.
- **Tiny footprint** — a few bytes every 5 s; the external IP is cached for 3 minutes.
- **Offline self-tests** — threshold logic, width contract and both translation tables are verified without a network.
- **Zero dependencies** — bash 3.2, `curl`, `awk`, `route`, `networksetup`. All shipped with macOS.

---

## Requirements

| Item | Detail |
|---|---|
| macOS | Tested on macOS 26. The Wi-Fi settings URL it uses has existed since Ventura (not verified below that). |
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | `brew install --cask swiftbar` |
| Xcode CLT | Only to build the optional SSID helper (`swiftc`). The plugin alone needs nothing. |

---

## Install

```sh
# 1. SwiftBar
brew install --cask swiftbar

# 2. this repository
git clone https://github.com/iconoclasteee/swiftbar-connection-health.git ~/dev/swiftbar-connection-health
chmod +x ~/dev/swiftbar-connection-health/plugins/connection.5s.sh

# 3. start SwiftBar and point it at the plugin folder
open -a SwiftBar
```

On first launch SwiftBar asks for a **plugin folder** → pick `~/dev/swiftbar-connection-health/plugins/`.

> That folder is deliberately separate from the repository root: SwiftBar runs **every** executable file in the folder it is given, README included.

**Optional** — show the Wi-Fi network name: see [Wi-Fi name helper](#wi-fi-name-helper).

---

## The dropdown

| Row | Content | Clickable |
|---|---|---|
| **Network** | Wi-Fi name + link type (Wi-Fi / iPhone USB / Bluetooth PAN…) | → macOS Wi-Fi settings |
| **Local IP** | private address; `169.254.x` is flagged as "no DHCP lease" | — |
| **Gateway** | router address, LAN side | → its admin interface |
| **External IP** | public address, cached 3 min — **it changes when you switch networks**, which confirms the switch actually happened | — |
| **Quality** | the full wording: healthy / good / fair / poor / offline / no internet | — |
| **Latency** | exact value in ms (TCP RTT) | — |
| **Raw network / DNS** | ✅ / ❌ — the two breakdown signals | — |
| **→ cause** | only when broken: "no network" / "DNS is down" / "the web is silent" | → Wi-Fi settings |
| **Checked at** | timestamp of the last run | — |

---

## Language

`UI_LANG` at the top of the plugin takes three values:

```bash
UI_LANG="auto"   # "fr" | "en" | "auto"
```

`auto` reads the macOS preferred language (`AppleLanguages`) and picks French for a French system, English for anything else. Set `fr` or `en` to pin it.

Adding a language means adding one `case` arm per key inside `t()`. The self-test walks every key in every language, so a missing arm fails the test instead of silently printing an empty row.

---

## Wi-Fi name helper

**The problem.** Since macOS Sonoma, reading the SSID requires the *Location Services* permission — the name of a network is enough to geolocate the machine. SwiftBar does not have it, so a plugin calling CoreWLAN directly receives `<redacted>`.

**The fix.** A 40-line signed mini-`.app`, no Dock icon, that holds the permission and prints the name. The grant is bound to the **binary's identity**, not to the network: you allow it **once**, and it survives Wi-Fi changes, reboots and macOS updates. The plugin caches the result for 30 s so the helper is not re-run on every refresh.

```sh
# 1. build + install
~/dev/swiftbar-connection-health/helper/build.sh

# 2. grant Location ONCE — a dialog appears in Terminal.app → "Allow"
"$HOME/Library/Application Support/connexion-menubar/WifiSSID.app/Contents/MacOS/WifiSSID" --grant
```

The binary has two modes: `--grant` (interactive, triggers the dialog) and no argument (reads the SSID, what the plugin calls).

- **Rebuilding** the helper changes its signature → run `--grant` once more.
- **Revoking**: Settings → Privacy & Security → Location Services → uncheck WifiSSID.
- **Without the helper** the plugin degrades cleanly: it shows the link type and says the name is hidden.

> The install path and bundle id still read `connexion-menubar`. That is not an oversight: the Location grant is tied to that identity, and renaming it would revoke the permission for everyone who already granted it.

---

## Settings

Everything sits in the `SETTINGS` block at the top of `plugins/connection.5s.sh`.

| Setting | Default | Effect |
|---|---|---|
| `UI_LANG` | `auto` | interface language: `fr`, `en`, or follow the system |
| `T_GREEN` / `T_YELLOW` / `T_ORANGE` | `80` / `150` / `280` ms | colour thresholds |
| `TIMEOUT` | `2` s | how long before the link is declared dead |
| `URL` | `gstatic.com/generate_204` | probe endpoint |
| `EXT_IP_TTL` | `180` s | external-IP cache lifetime |
| `SSID_TTL` | `30` s | Wi-Fi name cache lifetime |
| `BAR_FONT` | `Menlo-Regular` | menu bar font; `""` = system font |
| `BAR_SIZE` | `""` | font size; `""` = SwiftBar default |
| `INFO_LIGHT` / `INFO_DARK` | `#555555` / `#aaaaaa` | grey used by info rows, light / dark mode |
| refresh interval | `5s` **in the filename** | rename to `connection.3s.sh` for ~5 s reactivity instead of ~7 s |

> **Why Menlo and not SF Mono** — SF Mono is not usable here: macOS only exposes `.SF NS Mono`, an internal name `NSFont` refuses (checked via `NSFontManager`). Menlo ships with every macOS. With `BAR_FONT=""` numeric values stay aligned thanks to the figure space (below), only `-OFF-` and `LOGIN` shift slightly.

---

## How it works

### The probe

Every 5 s, **one** very light HTTP request to a "204" endpoint (`gstatic.com/generate_204`, a few bytes), from which three signals are extracted:

1. **TCP connect time** (`time_connect − time_namelookup`) = the latency shown. That is the handshake RTT, not the total request time.
2. **HTTP code** — `204` proves the intended server answered. Any other code means something interposed itself: that is the **captive portal** (hotel, airport, train Wi-Fi) → 🚫 `LOGIN`.
3. **curl's exit code** — non-zero means no HTTP answer at all → ⚫ `-OFF-`.

> **Why `http://` and not `https://`** — over HTTPS a captive portal would break TLS, curl would fail, and we would wrongly display "offline", losing the single most actionable piece of information ("go click *I agree*"). The price is a cleartext endpoint, which costs nothing here: we send no data and read only a status code.

**Only when the probe fails**, two DNS-independent probes split the cause apart: a TCP connection to a raw IP (`1.1.1.1`, no resolution) and a name lookup (`host`). Hence the three verdicts: *no network*, *network OK but DNS is down*, *network + DNS OK but the web is silent*. On the healthy path these never run — a successful request to a **name** already proves both network and DNS work.

### The constant width

Two mechanisms stack, which is what makes the result hold even if one is turned off:

1. **A monospace font** (`BAR_FONT`) — 5 characters means 5 identical widths, letters included.
2. **The figure space U+2007**, a space character exactly as wide as a digit. It replaces the ordinary space between value and unit, keeping numeric values aligned even under the proportional system font — because an ordinary space is *narrower* than a digit.

The formatting lives in a pure function `fmt_bar(state_key, latency)` whose contract — *always 5 characters* — is asserted by the self-test. Two details matter there:

- `09 ms` rather than ` 9 ms`: a leading zero is a real digit, so it cannot be trimmed the way a leading space can.
- Past 999 ms the **unit** is dropped, not the value (`1834`): four digits plus one filler take up roughly the same room as three digits plus "ms".

`state()` returns a language-independent key (`healthy`, `captive`, …) and translation happens only at print time. That keeps one source of truth for the state, and lets the tests assert on keys rather than on display strings.

### Local IP detection

`ipconfig getifaddr` only reports addresses handed out by the IPConfiguration service. On an iPhone Personal Hotspot the interface carries a `192.0.0.x` address that it does *not* report, which made the plugin claim "no DHCP lease" while the link was perfectly up. The plugin now falls back to parsing `ifconfig` before making that claim.

---

## Tests

The two pure functions and both translation tables are testable **without a network**:

```sh
cd ~/dev/swiftbar-connection-health/plugins
./connection.5s.sh --test     # thresholds + 5-character width contract + every i18n key
./connection.5s.sh            # real SwiftBar output (needs a network)
```

```text
ok    state(0 204 13) = 🟢|healthy
ok    fmt_bar(offline 0) = [-OFF-] (5 chars)
ok    fmt_bar(healthy 42) = [42 ms] (5 chars)
ok    fmt_bar(poor 1834) = [1834 ] (5 chars)
ok    t(fr, q_healthy) = sain
ok    t(en, q_healthy) = healthy
--- ALL TESTS PASS
```

The rest depends on a real network and is checked by hand:

- [ ] Normally connected → 🟢, latency close to a speed test
- [ ] Wi-Fi off → ⚫ `-OFF-` within ~7 s
- [ ] Hotel / airport Wi-Fi before signing in → 🚫 `LOGIN`
- [ ] Switch to a cellular hotspot → indicator and Network row update, external IP changes

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Plugin does not appear | file not executable, or plugin **added** without restarting SwiftBar | `chmod +x`, then `killall SwiftBar; open -a SwiftBar` |
| Dropdown rows are greyed out | older SwiftBar, or `bash=` removed from the row | see [SwiftBar notes](#swiftbar-notes) |
| Wi-Fi name missing | helper not built, or Location not granted | `helper/build.sh`, then `--grant` |
| ⚫ while the web works | `TIMEOUT` too short on a slow link | raise `TIMEOUT` to 3 – 4 s |
| Indicator looks too large | Menlo has a generous x-height | set `BAR_SIZE=12`, or `BAR_FONT=""` |
| Latency much higher than a speed test | expected: the TCP RTT includes the Wi-Fi hop and the router | compare against a `ping` of the gateway instead |
| Wrong interface language | system language is neither French nor English | pin `UI_LANG="en"` or `UI_LANG="fr"` |

---

## Repository layout

```text
swiftbar-connection-health/
├── plugins/
│   └── connection.5s.sh     # the plugin — settings, i18n, pure functions, probe, output
├── helper/
│   ├── agent.swift          # reads the SSID through CoreLocation
│   ├── Info.plist           # LSUIElement: no Dock icon
│   └── build.sh             # compiles, signs, installs the .app
├── README.md                # this file
├── README.fr.md             # French version
└── LICENSE
```

---

## SwiftBar notes

Three behaviours that cost time when discovered halfway through:

- **Adding a new plugin** (a new file) requires **restarting SwiftBar** — a refresh will not discover it. Editing an existing plugin: a refresh is enough.
- **Readable info rows** — macOS greys out *non-clickable* menu items. Making them "active" through a no-op action (`bash=/usr/bin/true`) lifts the forced grey **and** makes `color=` apply. Accepted side effect: rows highlight on hover, clicking does nothing.
- **Light / dark colours** — the `color=light,dark` syntax is **not** supported. The plugin detects the mode at runtime (`defaults read -g AppleInterfaceStyle`) and emits a single valid colour.

---

## Contributing

Issues and pull requests are welcome. Two things to keep in mind:

- `./plugins/connection.5s.sh --test` must pass. If you touch `fmt_bar`, add the case to the width assertions; if you touch `t()`, the key walk already covers you.
- The plugin targets **bash 3.2**, the version macOS ships as `/bin/bash`. No associative arrays, no `${var^^}`, no `$'\u…'`.

---

## Licence

[MIT](LICENSE) © Olivier Rhein
