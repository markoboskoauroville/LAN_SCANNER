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
