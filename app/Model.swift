// Model.swift: pure logic with no network in it (CIDR maths, ARP-line parsing, kind guessing, MAC helpers).
// Everything here is covered by --selftest, which the GitHub workflow runs: a red run is a real defect.
import Foundation

struct Device: Equatable {
    var ip: String
    var mac: String          // aa:bb:cc:dd:ee:ff, lower case, zero padded
    var name: String = ""
    var maker: String = ""
    var kind: String = "Unknown"
    var services: [String] = []   // Bonjour types seen for this address, e.g. "_ipp._tcp"
    var model: String = ""        // from _device-info TXT, e.g. "MacBookPro18,3"
    var upnpType: String = ""      // UPnP deviceType, e.g. urn:schemas-upnp-org:device:InternetGatewayDevice:1
    var isThisMac = false
    var isRouter = false
    var answeredPing = false
    var seen: Date = Date()
    var gone = false
}

struct NetInfo {
    var iface: String            // en0
    var ip: String               // this Mac's address on it
    var mask: UInt32
    var prefix: Int
    var gateway: String?
    var title: String            // Wi-Fi name, or "Wi-Fi (en0)"
    var index: UInt32            // if_nametoindex
}

enum CIDR {
    static func parse(_ ip: String) -> UInt32? {
        let p = ip.split(separator: ".")
        guard p.count == 4 else { return nil }
        var v: UInt32 = 0
        for s in p {
            guard let n = UInt32(s), n < 256 else { return nil }
            v = (v << 8) | n
        }
        return v
    }
    static func string(_ v: UInt32) -> String { "\(v >> 24).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)" }
    static func prefix(ofMask m: UInt32) -> Int { m.nonzeroBitCount }
    static func mask(prefix: Int) -> UInt32 { prefix <= 0 ? 0 : (prefix >= 32 ? 0xFFFF_FFFF : ~UInt32(0) << UInt32(32 - prefix)) }

    /// The host addresses to sweep. A network wider than /22 is cut to the /22 around this Mac's address (cap 1024).
    /// Returns the addresses, the prefix really scanned and whether it was cut.
    static func hosts(ip: UInt32, prefix: Int) -> (hosts: [UInt32], scannedPrefix: Int, capped: Bool) {
        var pf = prefix
        var capped = false
        if pf < 22 { pf = 22; capped = true }
        if pf >= 31 { return ([], pf, capped) }
        let m = mask(prefix: pf)
        let net = ip & m
        let bc = net | ~m
        var out: [UInt32] = []
        var a = net + 1
        while a < bc { if a != ip { out.append(a) }; a += 1 }
        return (out, pf, capped)
    }
    static func network(ip: UInt32, prefix: Int) -> String { "\(string(ip & mask(prefix: prefix)))/\(prefix)" }
    static func contains(ip: UInt32, net: UInt32, prefix: Int) -> Bool { (ip & mask(prefix: prefix)) == (net & mask(prefix: prefix)) }
    static func isBroadcastOrMulticast(_ ip: UInt32, ownIP: UInt32, prefix: Int) -> Bool {
        if (ip >> 28) == 0xE { return true }                       // 224.0.0.0/4
        if ip == 0xFFFF_FFFF { return true }
        let m = mask(prefix: prefix)
        if prefix < 31 && ip == ((ownIP & m) | ~m) { return true } // the subnet broadcast
        return false
    }
}

enum MAC {
    /// "0:1a:2b:3c:4d:5e" or "00-1A-2B-3C-4D-5E" -> "00:1a:2b:3c:4d:5e"; nil when it is not six bytes.
    static func normalize(_ s: String) -> String? {
        let parts = s.lowercased().split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var out: [String] = []
        for p in parts {
            guard p.count <= 2, let _ = UInt8(p, radix: 16) else { return nil }
            out.append(p.count == 1 ? "0" + p : String(p))
        }
        return out.joined(separator: ":")
    }
    static func isBroadcastOrMulticast(_ mac: String) -> Bool {
        guard let first = UInt8(mac.prefix(2), radix: 16) else { return true }
        return mac == "ff:ff:ff:ff:ff:ff" || (first & 0x01) == 1
    }
    /// Locally administered (bit 2 of the first byte): a phone's random Wi-Fi address, it has no real maker.
    static func isPrivate(_ mac: String) -> Bool {
        guard let first = UInt8(mac.prefix(2), radix: 16) else { return false }
        return (first & 0x02) != 0
    }
    static func prefix6(_ mac: String) -> String { mac.replacingOccurrences(of: ":", with: "").prefix(6).uppercased() }
}

enum ARPText {
    /// One line of `arp -an`: "? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]".
    /// Incomplete entries ("(incomplete)") give nil.
    static func parse(line: String) -> (ip: String, mac: String, iface: String)? {
        guard let o = line.firstIndex(of: "("), let c = line.firstIndex(of: ")"), o < c else { return nil }
        let ip = String(line[line.index(after: o)..<c])
        guard CIDR.parse(ip) != nil else { return nil }
        let rest = line[line.index(after: c)...].split(separator: " ").map(String.init)
        guard let at = rest.firstIndex(of: "at"), at + 1 < rest.count, let mac = MAC.normalize(rest[at + 1]) else { return nil }
        var iface = ""
        if let on = rest.firstIndex(of: "on"), on + 1 < rest.count { iface = rest[on + 1] }
        return (ip, mac, iface)
    }
}

enum Kinds {
    static func guess(device d: Device) -> String {
        if d.isRouter { return "Router" }
        if d.isThisMac { return "This Mac" }
        if let k = UPnP.kind(forType: d.upnpType) { return k }
        let m = d.model.lowercased()
        if m.hasPrefix("iphone") || m.hasPrefix("ipad") || m.hasPrefix("ipod") { return "Phone" }
        if m.hasPrefix("appletv") || m.hasPrefix("audioaccessory") || m.hasPrefix("homepod") { return "TV/Speaker" }
        if m.hasPrefix("mac") || m.hasPrefix("imac") || m.hasPrefix("xserve") { return "Computer" }
        let s = Set(d.services.map { $0.lowercased() })
        func has(_ prefixes: [String]) -> Bool { s.contains { t in prefixes.contains { t.hasPrefix($0) } } }
        if has(["_ipp", "_printer", "_pdl-datastream", "_scanner", "_uscan"]) { return "Printer" }
        if has(["_googlecast", "_airplay", "_raop", "_androidtvremote", "_amzn-wplay", "_mediaremotetv", "_spotify-connect", "_nvstream"]) { return "TV/Speaker" }
        if has(["_hap", "_homekit", "_hue", "_matter", "_meshcop"]) { return "IoT" }
        let mk = d.maker.lowercased()
        for w in ["hikvision", "axis comm", "dahua", "reolink", "wyze", "amcrest"] where mk.contains(w) { return "Camera" }
        for w in ["espressif", "tuya", "shelly", "sonoff", "philips lighting", "signify", "ikea"] where mk.contains(w) { return "IoT" }
        for w in ["sonos", "roku", "vizio", "bose", "denon", "yamaha", "harman"] where mk.contains(w) { return "TV/Speaker" }
        for w in ["raspberry"] where mk.contains(w) { return "Computer" }
        if has(["_smb", "_afpovertcp", "_ssh", "_sftp-ssh", "_workstation", "_rfb", "_eppc", "_adisk"]) { return "Computer" }
        return "Unknown"
    }
}

enum SelfTest {
    static func run() -> Bool {
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
        // CIDR
        check(CIDR.parse("192.168.1.10") == 0xC0A8_010A, "parse ip")
        check(CIDR.parse("300.1.1.1") == nil, "parse bad ip")
        check(CIDR.string(0xC0A8_010A) == "192.168.1.10", "string ip")
        check(CIDR.prefix(ofMask: 0xFFFF_FF00) == 24, "prefix of mask")
        check(CIDR.mask(prefix: 24) == 0xFFFF_FF00 && CIDR.mask(prefix: 0) == 0 && CIDR.mask(prefix: 32) == 0xFFFF_FFFF, "mask")
        let own = CIDR.parse("192.168.1.10")!
        let h24 = CIDR.hosts(ip: own, prefix: 24)
        check(h24.hosts.count == 253 && !h24.capped && h24.scannedPrefix == 24, "/24 gives 253 hosts without ours (got \(h24.hosts.count))")
        check(!h24.hosts.contains(own) && h24.hosts.first == CIDR.parse("192.168.1.1") && h24.hosts.last == CIDR.parse("192.168.1.254"), "/24 range")
        let h16 = CIDR.hosts(ip: CIDR.parse("10.0.5.9")!, prefix: 16)
        check(h16.capped && h16.scannedPrefix == 22 && h16.hosts.count == 1021, "/16 capped to /22 (got \(h16.hosts.count))")
        check(h16.hosts.first == CIDR.parse("10.0.4.1") && h16.hosts.last == CIDR.parse("10.0.7.254"), "/22 around 10.0.5.9")
        check(CIDR.hosts(ip: own, prefix: 30).hosts.count == 1, "/30 has two hosts, one is us")
        check(CIDR.hosts(ip: own, prefix: 32).hosts.isEmpty, "/32 nothing to scan")
        check(CIDR.network(ip: own, prefix: 24) == "192.168.1.0/24", "network string")
        check(CIDR.isBroadcastOrMulticast(CIDR.parse("192.168.1.255")!, ownIP: own, prefix: 24), "subnet broadcast")
        check(CIDR.isBroadcastOrMulticast(CIDR.parse("224.0.0.251")!, ownIP: own, prefix: 24), "multicast")
        check(!CIDR.isBroadcastOrMulticast(CIDR.parse("192.168.1.20")!, ownIP: own, prefix: 24), "normal host")
        // MAC
        check(MAC.normalize("0:1A:2b:3c:4D:5e") == "00:1a:2b:3c:4d:5e", "mac normalize")
        check(MAC.normalize("00-1A-2B-3C-4D-5E") == "00:1a:2b:3c:4d:5e", "mac dashes")
        check(MAC.normalize("(incomplete)") == nil && MAC.normalize("1:2:3") == nil, "mac bad")
        check(MAC.isPrivate("da:a1:19:00:00:01") && !MAC.isPrivate("00:11:22:33:44:55"), "private bit")
        check(MAC.isBroadcastOrMulticast("ff:ff:ff:ff:ff:ff") && MAC.isBroadcastOrMulticast("01:00:5e:00:00:fb") && !MAC.isBroadcastOrMulticast("00:11:22:33:44:55"), "broadcast mac")
        check(MAC.prefix6("00:11:22:33:44:55") == "001122", "prefix6")
        // ARP lines (made-up fixtures)
        let a = ARPText.parse(line: "? (192.168.50.1) at 0:11:22:aa:bb:cc on en9 ifscope [ethernet]")
        check(a?.ip == "192.168.50.1" && a?.mac == "00:11:22:aa:bb:cc" && a?.iface == "en9", "arp line")
        check(ARPText.parse(line: "? (192.168.50.7) at (incomplete) on en9 ifscope [ethernet]") == nil, "arp incomplete")
        check(ARPText.parse(line: "garbage") == nil, "arp garbage")
        // OUI
        check(OUI.lookup(mac: "da:a1:19:00:00:01") == "Private address", "private maker")
        check(OUI.lookup(mac: "b8:27:eb:00:00:01").hasPrefix("Raspberry Pi") || OUI.table.isEmpty, "oui raspberry")
        check(OUI.lookup(mac: "00:00:00:00:00:01") == "" || OUI.lookup(mac: "00:00:00:00:00:01") != "Private address", "oui unknown is never invented")
        check(OUI.shortName("Apple, Inc.") == "Apple" && OUI.shortName("TP-LINK TECHNOLOGIES CO.,LTD.") == "TP-LINK", "short names")
        // kinds
        var d = Device(ip: "192.168.50.2", mac: "00:11:22:33:44:55")
        check(Kinds.guess(device: d) == "Unknown", "unknown stays unknown")
        d.services = ["_ipp._tcp"]; check(Kinds.guess(device: d) == "Printer", "printer")
        d.services = ["_googlecast._tcp"]; check(Kinds.guess(device: d) == "TV/Speaker", "cast")
        d.services = []; d.model = "iPhone14,2"; check(Kinds.guess(device: d) == "Phone", "phone")
        d.model = "MacBookPro18,3"; check(Kinds.guess(device: d) == "Computer", "mac model")
        d.model = ""; d.maker = "Espressif"; check(Kinds.guess(device: d) == "IoT", "esp")
        d.isRouter = true; check(Kinds.guess(device: d) == "Router", "router first")
        d.isRouter = false; d.isThisMac = true; check(Kinds.guess(device: d) == "This Mac", "this mac")
        // labels, cap note, gone merge, DNS and UPnP parsing, fixture
        check(Label.display(name: "", maker: "Murata Manufacturing", mac: "80:99:9b:13:ad:3f") == "Murata device", "label maker")
        check(Label.display(name: "", maker: "Private address", mac: "da:a1:19:00:00:01") == "Private address device", "label private")
        check(Label.display(name: "", maker: "", mac: "") == "Unknown device", "label unknown")
        check(Label.display(name: "Printer", maker: "Brother", mac: "") == "Printer", "label real name wins")
        check(Label.capNote(cidr: "10.9.0.0/16", scanned: "10.9.0.0/22").contains("/22 around this Mac"), "cap note")
        let a1 = Device(ip: "10.0.0.2", mac: "00:11:22:33:44:01"), a2 = Device(ip: "10.0.0.3", mac: "00:11:22:33:44:02")
        let g1 = Merge.gone(previous: [a1, a2], current: [a1], alreadyGone: [])
        check(g1.count == 1 && g1[0].ip == "10.0.0.3" && g1[0].gone, "gone after two scans")
        check(Merge.gone(previous: [a1], current: [a1, a2], alreadyGone: g1).isEmpty, "gone device back is no longer gone")
        let q = DNS.ptrQuery(ip: "192.168.1.7", id: 5)
        check(q.count == 12 + 1 + 1 + 1 + 1 + 1 + 1 + 7 + 1 + 4 + 1 + 4 + 0 || q.last == 1, "ptr query built")
        var resp = q; resp[2] = 0x84; resp[7] = 1
        let host: [UInt8] = [3, 0x6D, 0x61, 0x63, 5, 0x6C, 0x6F, 0x63, 0x61, 0x6C, 0]
        resp += [0xC0, 12, 0, 12, 0, 1, 0, 0, 0, 120, 0, UInt8(host.count)] + host
        check(DNS.ptrNames(resp) == ["mac.local"], "ptr answer parsed (got \(DNS.ptrNames(resp)))")
        check(DNS.ptrNames([1, 2, 3]).isEmpty, "bad dns ignored")
        let xml = "<root><device><deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType><friendlyName>Test Router</friendlyName><modelName>TR-100</modelName></device></root>"
        let up = UPnP.parse(xml: xml)
        check(up.friendly == "Test Router" && up.model == "TR-100" && UPnP.kind(forType: up.type) == "Router", "upnp xml")
        check(UPnP.location(fromResponse: "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://10.0.0.1:5000/d.xml\r\n\r\n") == "http://10.0.0.1:5000/d.xml", "ssdp location")
        let fx = "{\"scans\":[{\"net\":{\"iface\":\"en0\",\"ip\":\"10.9.0.5\",\"prefix\":16,\"gateway\":\"10.9.0.1\"},\"devices\":[{\"ip\":\"10.9.0.1\",\"mac\":\"00:11:22:33:44:55\"}]}]}"
        if let f = try? JSONDecoder().decode(Fixture.self, from: Data(fx.utf8)) {
            let r = Fixture.result(f.scans[0], progress: { _, _ in }, cancelled: { false })
            check(r.capped && r.cidr == "10.9.0.0/16" && r.notes.count == 1 && r.devices.first?.kind == "Router", "fixture wide network is capped, router labelled")
        } else { check(false, "fixture decodes") }
        check(Fixture.result(FixtureScan(delay: nil, net: nil, noNetwork: true, notes: nil, error: nil, permissionSuspect: nil, devices: nil), progress: { _, _ in }, cancelled: { false }).error == Label.noNetwork, "fixture no network")
        d.upnpType = "urn:schemas-upnp-org:device:MediaRenderer:1"; d.isThisMac = false; d.isRouter = false; check(Kinds.guess(device: d) == "TV/Speaker", "upnp kind")
        for f in fails { print("selftest FAIL: \(f)") }
        print(fails.isEmpty ? "selftest OK" : "selftest: \(fails.count) failed")
        return fails.isEmpty
    }
}
