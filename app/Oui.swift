// Oui.swift: MAC prefix -> maker. The full table (oui.tsv, prefix TAB short name) is made in CI by tools/make_oui.py from
// the IEEE list and sits in the app's Resources. This file holds a small committed fallback of well-known prefixes for
// when that download failed (the build does not fail then). A MAC with the locally-administered bit is "Private address"
// and never gets a maker; an unknown prefix gives an empty string, never a guess.
import Foundation

enum OUI {
    static let fallbackText = """
    000393 Apple
    000502 Apple
    000A27 Apple
    000A95 Apple
    000D93 Apple
    0010FA Apple
    001124 Apple
    001451 Apple
    0016CB Apple
    0017F2 Apple
    0019E3 Apple
    001B63 Apple
    001CB3 Apple
    001D4F Apple
    001E52 Apple
    001EC2 Apple
    001FF3 Apple
    0021E9 Apple
    002241 Apple
    002312 Apple
    002332 Apple
    00236C Apple
    0023DF Apple
    002436 Apple
    002500 Apple
    00254B Apple
    0025BC Apple
    002608 Apple
    00264A Apple
    0026B0 Apple
    0026BB Apple
    3C0754 Apple
    28CFE9 Apple
    F01898 Apple
    A483E7 Apple
    B827EB Raspberry Pi
    DCA632 Raspberry Pi
    E45F01 Raspberry Pi
    28CDC1 Raspberry Pi
    D83ADD Raspberry Pi
    240AC4 Espressif
    30AEA4 Espressif
    246F28 Espressif
    840D8E Espressif
    A4CF12 Espressif
    7C9EBD Espressif
    3C71BF Espressif
    ECFABC Espressif
    5CCF7F Espressif
    18FE34 Espressif
    600194 Espressif
    CC50E3 Espressif
    2462AB Espressif
    8CAAB5 Espressif
    3C5AB4 Google
    F4F5D8 Google
    546009 Google
    A47733 Google
    1CF29A Google
    001247 Samsung
    001599 Samsung
    001632 Samsung
    0017D5 Samsung
    001B21 Intel
    001E64 Intel
    3C970E Intel
    0013E8 Intel
    50C7BF TP-Link
    14CC20 TP-Link
    F4F26D TP-Link
    98DAC4 TP-Link
    EC086B TP-Link
    54AF97 TP-Link
    00155D Microsoft
    0050F2 Microsoft
    000C29 VMware
    005056 VMware
    000569 VMware
    000E58 Sonos
    5CAAFD Sonos
    7828CA Sonos
    44650D Amazon
    74C246 Amazon
    F0D2F1 Amazon
    00095B Netgear
    00146C Netgear
    00000C Cisco
    002722 Ubiquiti
    24A43C Ubiquiti
    44D9E7 Ubiquiti
    788A20 Ubiquiti
    0013A9 Sony
    001A80 Sony
    FC0FE6 Sony
    001C62 LG
    008077 Brother
    0001E6 HP
    000085 Canon
    000048 Epson
    080027 VirtualBox
    """

    static let fallback: [String: String] = {
        var t: [String: String] = [:]
        for line in fallbackText.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard let sp = s.firstIndex(of: " ") else { continue }
            let key = String(s[..<sp])
            let rest = String(s[s.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
            if key.count == 6 { t[key.uppercased()] = rest }
        }
        return t
    }()

    /// The CI table, loaded once from Resources/oui.tsv (absent when the download failed).
    static let table: [String: String] = {
        var t: [String: String] = [:]
        guard let p = Bundle.main.path(forResource: "oui", ofType: "tsv"),
              let s = try? String(contentsOfFile: p, encoding: .utf8) else { return t }
        for line in s.split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 1)
            if f.count == 2 { t[String(f[0])] = String(f[1]) }
        }
        return t
    }()

    static func lookup(mac: String) -> String {
        if MAC.isPrivate(mac) { return "Private address" }
        let k = MAC.prefix6(mac)
        return table[k] ?? fallback[k] ?? ""
    }

    /// "Apple, Inc." -> "Apple", "TP-LINK TECHNOLOGIES CO.,LTD." -> "TP-LINK".
    static func shortName(_ full: String) -> String {
        var s = full.replacingOccurrences(of: ",", with: " ")
        let drop: Set<String> = ["inc", "inc.", "ltd", "ltd.", "co", "co.", "corp", "corp.", "corporation", "gmbh", "llc", "limited",
                                 "technologies", "technology", "company", "s.a.", "ag", "b.v.", "plc", "co.,ltd.", "co.ltd."]
        var words = s.split(separator: " ").map(String.init)
        while let last = words.last, drop.contains(last.lowercased()) || drop.contains(last.lowercased().replacingOccurrences(of: ".", with: "")) {
            words.removeLast()
        }
        s = words.joined(separator: " ")
        return s.isEmpty ? full : String(s.prefix(28))
    }
}
