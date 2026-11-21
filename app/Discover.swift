// Discover.swift: more name sources (mDNS reverse lookup, SSDP/UPnP), the "no name" label, the "gone" merge and the fixture
// feed used by --fixture to prove window paths without a real network. The parsing is pure and covered by --selftest.
import Foundation
import Darwin

enum Label {
    /// What the Name cell shows. A real name when there is one; otherwise the maker in plain words. Never invented.
    static func display(name: String, maker: String, mac: String) -> String {
        if !name.isEmpty { return name }
        if maker == "Private address" || (maker.isEmpty && !mac.isEmpty && MAC.isPrivate(mac)) { return "Private address device" }
        if let w = maker.split(separator: " ").first, !maker.isEmpty { return "\(w) device" }
        return "Unknown device"
    }
    static func capNote(cidr: String, scanned: String) -> String {
        "The network is \(cidr), too wide: scanned only the /22 around this Mac (\(scanned))."
    }
    static let noNetwork = "No network: this Mac has no active IPv4 network."
}

extension Device {
    var displayName: String { Label.display(name: name, maker: maker, mac: mac) }
}

enum Merge {
    /// Devices of the last scan that are not in this one stay in the list as grey "gone" rows (until the next launch).
    static func gone(previous: [Device], current: [Device], alreadyGone: [Device]) -> [Device] {
        let now = Set(current.map { $0.ip })
        var g = alreadyGone.filter { !now.contains($0.ip) }
        for d in previous where !now.contains(d.ip) && !g.contains(where: { $0.ip == d.ip }) { var x = d; x.gone = true; g.append(x) }
        return g
    }
}

enum DNS {
    /// PTR query for an address ("1.0.168.192.in-addr.arpa"), QU bit set so the answer comes back unicast.
    static func ptrQuery(ip: String, id: UInt16) -> [UInt8] {
        var p: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for part in Array(ip.split(separator: ".").map(String.init).reversed()) + ["in-addr", "arpa"] {
            let b = Array(part.utf8); p.append(UInt8(b.count)); p += b
        }
        p += [0, 0, 12, 0x80, 1]
        return p
    }

    static func readName(_ d: [UInt8], _ start: Int) -> (String, Int)? {
        var i = start, labels: [String] = [], next = -1, hops = 0
        while i < d.count {
            let l = Int(d[i])
            if l == 0 { return (labels.joined(separator: "."), next >= 0 ? next : i + 1) }
            if l & 0xC0 == 0xC0 {
                guard i + 1 < d.count, hops < 10 else { return nil }
                if next < 0 { next = i + 2 }
                i = ((l & 0x3F) << 8) | Int(d[i + 1]); hops += 1; continue
            }
            guard i + 1 + l <= d.count else { return nil }
            labels.append(String(decoding: d[(i + 1)..<(i + 1 + l)], as: UTF8.self)); i += 1 + l
        }
        return nil
    }

    /// The PTR names in the answers of a DNS message.
    static func ptrNames(_ d: [UInt8]) -> [String] {
        guard d.count > 12 else { return [] }
        let qd = Int(d[4]) << 8 | Int(d[5]), an = Int(d[6]) << 8 | Int(d[7])
        var i = 12
        for _ in 0..<qd { guard let (_, n) = readName(d, i) else { return [] }; i = n + 4 }
        var out: [String] = []
        for _ in 0..<an {
            guard let (_, n) = readName(d, i), n + 10 <= d.count else { break }
            let type = Int(d[n]) << 8 | Int(d[n + 1]), rdlen = Int(d[n + 8]) << 8 | Int(d[n + 9])
            if type == 12, let (nm, _) = readName(d, n + 10) { out.append(nm) }
            i = n + 10 + rdlen
        }
        return out
    }
}

enum UPnP {
    static let msearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: upnp:rootdevice\r\n\r\n"

    static func location(fromResponse s: String) -> String? {
        for line in s.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("location:") {
            return line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    static func tag(_ xml: String, _ name: String) -> String {
        guard let a = xml.range(of: "<\(name)>"), let b = xml.range(of: "</\(name)>", range: a.upperBound..<xml.endIndex) else { return "" }
        return String(xml[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// friendlyName, modelName and deviceType of a device description.
    static func parse(xml: String) -> (friendly: String, model: String, type: String) {
        (tag(xml, "friendlyName"), tag(xml, "modelName"), tag(xml, "deviceType"))
    }
    static func kind(forType t: String) -> String? {
        let l = t.lowercased()
        if l.contains("internetgatewaydevice") { return "Router" }
        if l.contains("mediarenderer") { return "TV/Speaker" }
        if l.contains("printer") { return "Printer" }
        return nil
    }
}

struct Found { var mdns = ""; var friendly = ""; var model = ""; var type = "" }

enum Probe {
    /// mDNS reverse lookup (multicast and unicast to port 5353) and SSDP (multicast and unicast to port 1900), short timeouts.
    static func run(ips: [UInt32], net: NetInfo, ms: Int32 = 1800, cancelled: () -> Bool) -> [String: Found] {
        var out: [String: Found] = [:]
        let m = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP), s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        defer { if m >= 0 { close(m) }; if s >= 0 { close(s) } }
        guard m >= 0 || s >= 0 else { return out }
        var ownAddr = in_addr(s_addr: (CIDR.parse(net.ip) ?? 0).bigEndian)
        for fd in [m, s] where fd >= 0 {
            Wire.nonblocking(fd); Wire.bind(fd, toInterface: net.index)
            _ = setsockopt(fd, IPPROTO_IP, 9 /* IP_MULTICAST_IF */, &ownAddr, socklen_t(MemoryLayout<in_addr>.size))
        }
        let mcastMDNS = CIDR.parse("224.0.0.251")!, mcastSSDP = CIDR.parse("239.255.255.250")!
        let ssdp = Array(UPnP.msearch.utf8)
        if s >= 0 { _ = Wire.send(s, ssdp, to: mcastSSDP, port: 1900) }
        var idToIP: [UInt16: UInt32] = [:]
        var id: UInt16 = 1
        for ip in ips {
            if cancelled() { break }
            if m >= 0 {
                let q = DNS.ptrQuery(ip: CIDR.string(ip), id: id); idToIP[id] = ip; id &+= 1
                _ = Wire.send(m, q, to: ip, port: 5353)
                _ = Wire.send(m, q, to: mcastMDNS, port: 5353)
            }
            if s >= 0 { _ = Wire.send(s, ssdp, to: ip, port: 1900) }
        }
        var locations: [String: String] = [:]
        var fds: [pollfd] = []
        if m >= 0 { fds.append(pollfd(fd: m, events: Int16(POLLIN), revents: 0)) }
        if s >= 0 { fds.append(pollfd(fd: s, events: Int16(POLLIN), revents: 0)) }
        let end = Date().addingTimeInterval(Double(ms) / 1000)
        while !cancelled() {
            let left = Int32(max(0, end.timeIntervalSinceNow * 1000))
            for i in fds.indices { fds[i].revents = 0 }
            if poll(&fds, nfds_t(fds.count), left) <= 0 { break }
            for f in fds where f.revents & Int16(POLLIN) != 0 {
                var buf = [UInt8](repeating: 0, count: 4096)
                var from = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) { fp in
                    fp.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { recvfrom(f.fd, &buf, buf.count, 0, $0, &len) }
                }
                guard n > 0 else { continue }
                let src = CIDR.string(UInt32(bigEndian: from.sin_addr.s_addr))
                let data = Array(buf[0..<n])
                if f.fd == m {
                    if let name = DNS.ptrNames(data).first(where: { !$0.isEmpty }) {
                        var e = out[src] ?? Found(); if e.mdns.isEmpty { e.mdns = Names.shorten(name) }; out[src] = e
                    }
                } else if let loc = UPnP.location(fromResponse: String(decoding: data, as: UTF8.self)) {
                    locations[src] = loc
                }
            }
        }
        // device descriptions: only from the device's own address, 1.5 s each, all in parallel
        let g = DispatchGroup(), lock = NSLock()
        for (ip, loc) in locations where !cancelled() {
            guard let url = URL(string: loc), url.host == ip, url.scheme == "http" else { continue }
            g.enter()
            var req = URLRequest(url: url); req.timeoutInterval = 1.5
            URLSession.shared.dataTask(with: req) { data, _, _ in
                if let d = data, let xml = String(data: d, encoding: .utf8) {
                    let p = UPnP.parse(xml: xml)
                    lock.lock(); var e = out[ip] ?? Found(); e.friendly = p.friendly; e.model = p.model; e.type = p.type; out[ip] = e; lock.unlock()
                }
                g.leave()
            }.resume()
        }
        _ = g.wait(timeout: .now() + 2.2)
        lock.lock(); defer { lock.unlock() }
        return out
    }
}

// MARK: fixture (--fixture file.json): made-up scans, one per SCAN press, the last one repeats

struct FixtureDevice: Codable { var ip: String; var mac: String; var name: String?; var maker: String?; var kind: String? }
struct FixtureNet: Codable { var iface: String; var ip: String; var prefix: Int; var gateway: String?; var title: String? }
struct FixtureScan: Codable {
    var delay: Double?                 // seconds the fake scan takes (so STOP can be pressed)
    var net: FixtureNet?
    var noNetwork: Bool?
    var notes: [String]?
    var error: String?
    var permissionSuspect: Bool?
    var devices: [FixtureDevice]?
}
struct Fixture: Codable {
    var scans: [FixtureScan]
    var others: [FixtureNet]?
    static var current: Fixture? = nil
    static var index = 0
    static func load(_ path: String) -> Fixture? {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(Fixture.self, from: d)
    }
    static func info(_ n: FixtureNet) -> NetInfo {
        return NetInfo(iface: n.iface, ip: n.ip, mask: CIDR.mask(prefix: n.prefix), prefix: n.prefix, gateway: n.gateway, title: n.title ?? n.iface, index: 0)
    }
    /// The fake scan: waits `delay` (honouring STOP), then builds the result with the real cap logic and notes.
    static func result(_ s: FixtureScan, progress: (Double, String) -> Void, cancelled: () -> Bool) -> ScanResult {
        var r = ScanResult()
        let steps = max(1, Int((s.delay ?? 0) * 10))
        for i in 0..<steps {
            if cancelled() { r.error = "Stopped."; return r }
            progress(Double(i) / Double(steps), "Sweeping (fixture)")
            Thread.sleep(forTimeInterval: (s.delay ?? 0) / Double(steps))
        }
        if s.noNetwork == true { r.error = Label.noNetwork; return r }
        if let n = s.net {
            let ni = info(n); r.net = ni
            if let own = CIDR.parse(n.ip) {
                let plan = CIDR.hosts(ip: own, prefix: n.prefix)
                r.cidr = CIDR.network(ip: own, prefix: n.prefix); r.capped = plan.capped
                if plan.capped { r.notes.append(Label.capNote(cidr: r.cidr, scanned: CIDR.network(ip: own, prefix: plan.scannedPrefix))) }
            }
        }
        r.notes += s.notes ?? []
        r.error = s.error; r.permissionSuspect = s.permissionSuspect ?? false
        r.devices = (s.devices ?? []).map {
            var d = Device(ip: $0.ip, mac: $0.mac); d.name = $0.name ?? ""; d.maker = $0.maker ?? OUI.lookup(mac: $0.mac)
            d.isRouter = $0.ip == s.net?.gateway; d.isThisMac = $0.ip == s.net?.ip
            d.kind = $0.kind ?? Kinds.guess(device: d); d.seen = Date(); return d
        }
        return r
    }
    static func next() -> FixtureScan? {
        guard let f = current, !f.scans.isEmpty else { return nil }
        let s = f.scans[min(index, f.scans.count - 1)]; index += 1; return s
    }
}
