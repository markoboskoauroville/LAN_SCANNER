#!/bin/bash
# Guard "one title only" (MANTRA_MANIFEST modules/one-title-only.md): fails when the window can show a second title.
cd "$(dirname "$0")/app" || exit 1
fail=0
grep -q "titleVisibility = .hidden" App.swift || { echo "FAIL window never hides the system title"; fail=1; }
grep -q "func enforceOneTitle" App.swift || { echo "FAIL enforceOneTitle() is missing"; fail=1; }
for h in windowDidBecomeKey windowDidResize windowDidEnterFullScreen windowDidExitFullScreen; do
  grep -A8 "func $h" App.swift | grep -q enforceOneTitle || { echo "FAIL $h does not call enforceOneTitle"; fail=1; }
done
grep -q "titleVisibility = .visible" *.swift && { echo "FAIL titleVisibility = .visible found"; fail=1; }
[ $fail = 0 ] && echo "one title only: OK"
exit $fail
