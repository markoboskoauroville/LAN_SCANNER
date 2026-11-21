# TAKEOVER: LAN Scanner (Mantra)

Public, unpromoted repository: no README and no description by rule (MANTRA_MANIFEST modules/repo-privacy.md). This file says what the project is.

**What it is.** A Mac app (Swift, macOS 14+) that shows every device on the network this Mac is on now. One window, one button, SCAN (STOP while it runs); a scan also runs when the window opens. Table: Name, IP, MAC, Maker, Kind, Seen. Header: network name, this Mac's address, subnet, router, device count. Click a row = copy the IP. Devices that vanished stay grey as "gone" until the next launch. Asked by Marko on 21.11.2026 (words in momentaryupdates.md); "store" is read as the star.

**Build.** Only GitHub compiles (.github/workflows/mac-swift.yml, macos-15): one-title guard, IEEE OUI download (tools/make_oui.py, never fails the build), build.sh, `--selftest` (a red run is a real defect), release vN Latest with app.zip. The Mac downloads the release, unzips to /Applications and signs "Mantra Apps" (bundle id community.auroville.lanscanner). Version = `let VERSION` in app/App.swift, whole numbers.

**Engine (app/Engine.swift).** Interface with the default route (route -n get default, getifaddrs; utun/bridge/awdl skipped); sweep with an unprivileged ICMP socket plus a NetBIOS node-status query over UDP/137 to every host (batches of 64, two passes, /22 cap); the ARP table read with sysctl (NET_RT_FLAGS, RTF_LLINFO) as the truth, `arp -an` as fallback; names from Bonjour (NetServiceBrowser over a fixed type list that Info.plist NSBonjourServices repeats), reverse DNS, NetBIOS; maker from Resources/oui.tsv (CI) or the small fallback in app/Oui.swift; "Private address" for locally administered MACs; kind guess in app/Model.swift (Unknown is allowed, wrong is not). Errors are shown, never silent.

**Local Network (macOS 15).** Without the permission sends fail or the ARP table stays empty: the window shows an error line and the amber PERMISSIONS button (opens System Settings > Privacy & Security > Local Network). The permission is tied to the signature: always sign "Mantra Apps" with the same bundle id.

**Headless.** `"/Applications/LAN Scanner (Mantra).app/Contents/MacOS/LAN Scanner (Mantra)" --json` (also `--iface en5`), `--selftest`, `--studio-shot <png> [--width N]`. Terminal command `lanscan` (~/.local/bin, not in the repo) prints a table. Queen skill lan-scan (groq_ai_studio) answers "which devices are on my network".

**Window.** Plain NSWindow, resizable, frame autosave, minimum content size 760 x 360 enforced also for programmatic resizes, own title once (system title hidden, check_one_title.sh), version visible, window X quits, every control an Accessibility button with an identifier (scan, stop, permissions, net-<iface>, row-<ip>) and a readable AXDescription.

**Star.** Row `lanscanner` in STAR_SWIFT rows.json (group Networking), icon LAN/SCN over the wifi symbol (icon/six_1024.png).

**Not proven.** Bonjour names (no service is advertised on the test network), the Local Network prompt for a fresh signature, a network wider than /22 live, two real LAN interfaces at once.
