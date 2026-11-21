# momentaryupdates.md

## 21.11.2026, Marko's request, word for word

"Please build up a LAN scanner which is going to show me every device on the current network. It's my mantra. Apps going to the store. Fable is as usual write this in the manifest only creating the plan workers are working in appropriate models and Fable is giving score until we score 10 of 10. Write this in the manifest mantra manifest."

Reading: a Mantra Mac app in Swift, "LAN Scanner (Mantra)". "The store" is read as "the star" (his dictation), so it gets a row in the star (STAR_SWIFT rows.json). Rule for the build loop: MANTRA_MANIFEST modules/fable-plans-and-scores.md (Fable plans and scores, workers build, until 10 of 10).

## The workflow

1. Repository markoboskoauroville/LAN_SCANNER, public, branch main, no README, no description.
2. Only GitHub compiles (.github/workflows/mac-swift.yml); the Mac downloads the release, installs to /Applications, signs "Mantra Apps".
3. The plan: one window, a table of every device on the current network (Name, IP, MAC, Maker, Kind, Seen), one button SCAN. Pure Swift engine: interface and default route, ping and UDP sweep, the ARP cache as truth, Bonjour, reverse DNS and NetBIOS names, OUI makers, kind guesses. Headless: --json, --selftest, --studio-shot.
4. Fable scores the real result out of 10; corrections go back until it is 10.

## Status 21.11.2026
v3 installed and signed; Fable scores: v1 6, v2 7 of 10; v3 awaiting score. See LESSONS.md Scores.
