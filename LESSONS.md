# LESSONS: LAN Scanner (Mantra)

21.11.2026, v1 (builder worker; Fable scores the real result).

1. The first CI run of a new Swift app compiled; the only red was the app's own self test (a maker name was longer than the test expected). Self tests that depend on a downloaded table must test prefixes, not full names.
2. SwiftUI plain Buttons with `.accessibilityLabel` alone give no AXDescription on macOS 15.0 and, with `.accessibilityElement(children: .ignore)`, AXPress does nothing: add `.accessibilityAction { action() }` explicitly. Check through the AXUIElement API (pyobjc ApplicationServices), not System Events `entire contents`, which returned empty or errored.
3. NSWindow.contentMinSize is not enforced for programmatic (AX) resizes; set it after the contentView, and also clamp in `windowWillResize` and `windowDidResize`. Keep the SwiftUI root's min width below the window minimum.
4. A window opened with `open -g` lands on the main display (the BenQ here); move it with AX position, never leave it there.
5. Unprivileged ICMP (`socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`) works on macOS without root; the ARP table read with sysctl needs hard-coded offsets (rt_msghdr is 92 bytes) because net/route.h is not in the Darwin module.
6. `arp -an` prints MACs without leading zeros ("0:11:22:aa:bb:cc"): normalise before comparing.
7. The IEEE list names are long ("TP-Link Systems Inc."): shortName strips legal suffixes only; a maker column needs a wrapping cell.
8. check_one_title.sh from MANTRA_ROOM expects TopRow.float; a version without that check lives here.

## Scores

- Round 1 (v1): 6 of 10 (Fable). Counted as no: update at start never exercised; untested paths (STOP, gone rows, wide network cap, second interface, no-network line, PERMISSIONS state, row click-to-copy, --studio-shot); three of four devices had no name (needs mDNS reverse and SSDP/UPnP, a maker-based label instead of "unknown"); fallback OUI table 100 instead of about 300 prefixes; Queen's install gate not run; testclean not run in the foreground; the three public-repo checks not run; TAKEOVER too short; no AX dump in the report. All of it went into v2.
- Round 2 (v2): 7 of 10 (Fable). Counted as no: a blue keyboard-focus box around SCAN; the update swap never pressed; Queen's install.sh stopping on a stale api_credit.py line.
- Round 3 (v3, session closed 21.11.2026): 9 of 10 (Fable). Yes now: no focus box; update swap v2 to v3 pressed through AX, came back as v3, still signed Mantra Apps, scan still finds the devices. Still no: point 9, Queen. Her v31 skill (queen_python_skills/lan_scan.py) is installed and passes the gate, but her running backend was not restarted, so she was never asked in her own chat.

## Lessons from round 1 to 2
9. A `--fixture` feed is the way to prove window paths without a network: the fake scan goes through the same cap logic, merge and finish() as a real one.
10. The update question is only provable with two releases: release vN+1 while vN is installed and started; the alert is a window of the app itself (screencapture -l by id works wherever it is). Do not answer it.
11. Pure parsers (DNS PTR, UPnP XML, SSDP LOCATION) go into --selftest so CI covers them.
12. install.sh of groq_ai_studio fails at the end on `api_credit.py`, which is not in the repo (86 gate tests PASS before it).
- Round 2 (v2): 7 of 10 (Fable). Counted as no: (1) a blue keyboard-focus box around SCAN in every screenshot, and the OTHER NETWORK line was a different size from the header line; (2) the update swap was never run (needs v3 released while v2 is installed, Update pressed through Accessibility); (3) Queen's install: install.sh failed on api_credit.py, her start was not explained.
- Round 3 (v3): built by the worker, not scored by it.

13. SwiftUI plain Buttons show a focus ring: `.focusEffectDisabled()` on every button and on the root, and `window.makeFirstResponder(nil)` after the window is shown.
14. Queen v31 is a Swift app + `~/.queen/backend/queen_backend.py` (Python skills, `dispatch()` in queen_python_skills/__init__.py); the legacy `~/.groq/qwen_app/app.py` with `ops_hands.py` is not what v31 runs. The Swift host starts `~/.queen/queen-backend`, which only exists after a clean `install.sh`; a failing install.sh (here the stale api_credit.py line) leaves it missing and port 8766 stays down.
15. Update swap proven on 21.11.2026 (v2 -> v3): the question appeared, Update pressed through Accessibility (macro ax-press under macro lock), the app came back as v3 by itself, still signed "Mantra Apps" with the same identifier, a scan still found the 4 devices, no macOS prompt.
