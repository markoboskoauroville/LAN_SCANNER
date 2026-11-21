// Engine.swift: the scan. Pure Swift, no root, no tool shipped. Steps: find the network (default route), sweep every host
// (unprivileged ICMP echo + a NetBIOS query over UDP so the kernel resolves ARP even for hosts that drop ping), read the ARP
// cache as the truth, then names (Bonjour, reverse DNS, NetBIOS), maker (OUI) and kind.
import Foundation
import Darwin
import CoreWLAN

struct ScanResult {
    var net: NetInfo?
    var devices: [Device] = []
    var cidr = ""
    var capped = false
    var notes: [String] = []        // plain lines for the window ("Scanned the /22 around this Mac ...")
    var error: String? = nil        // shown in red-ish; never silent
    var permissionSuspect = false   // Local Network access probably off: amber PERMISSIONS
}

enum Sh {
    /// Runs a tool and returns its stdout, nil on failure or timeout.
    static func run(_ exe: String, _ args: [String], timeout: Double = 5) -> String? {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        var data = Data()
        let g = DispatchGroup(); g.enter()
        DispatchQueue.global().async { data = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        if g.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

enum Net {
    static let skipPrefixes = ["lo", "utun", "bridge", "awdl", "llw", "gif", "stf", "ap", "anpi", "pktap", "vmenet", "ipsec", "ppp"]

    static func activeInterfaces() -> [NetInfo] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var out: [NetInfo] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            p = a.pointee.ifa_next
            let name = String(cString: a.pointee.ifa_name)
            let flags = Int32(a.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            if skipPrefixes.contains(where: { name.hasPrefix($0) }) { continue }
            guard let addr = a.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let nm = a.pointee.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if (ip >> 16) == 0xA9FE { continue }          // 169.254 link-local: no network
            let pf = CIDR.prefix(ofMask: mask)
            if pf >= 31 || pf == 0 { continue }
            if out.contains(where: { $0.iface == name }) { continue }
            out.append(NetInfo(iface: name, ip: CIDR.string(ip), mask: mask, prefix: pf, gateway: nil,
                               title: name, index: if_nametoindex(name)))
        }
        for i in out.indices {
            out[i].gateway = gateway(for: out[i].iface)
            out[i].title = title(for: out[i].iface)
        }
        return out
    }

    /// The interface that carries the default route ("the current network"), else the first one with a gateway.
    static func current(from list: [NetInfo]) -> NetInfo? {
        if let r = Sh.run("/sbin/route", ["-n", "get", "default"]) {
            for line in r.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("interface:") {
                    let n = t.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
                    if let hit = list.first(where: { $0.iface == n }) { return hit }
                }
            }
        }
        return list.first(where: { $0.gateway != nil && $0.iface.hasPrefix("en") }) ?? list.first(where: { $0.gateway != nil }) ?? list.first
    }

    static func gateway(for iface: String) -> String? {
        guard let t = Sh.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]) else { return nil }
        for line in t.split(separator: "\n") {
            let f = line.split(separator: " ").map(String.init)
            if f.count >= 4, f[0] == "default", CIDR.parse(f[1]) != nil, f.contains(iface) { return f[1] }
        }
        return nil
    }

    static func title(for iface: String) -> String {
        if let ssid = CWWiFiClient.shared().interface(withName: iface)?.ssid(), !ssid.isEmpty { return ssid }
        if let t = Sh.run("/usr/sbin/networksetup", ["-listallhardwareports"]) {
            var port = ""
            for line in t.split(separator: "\n") {
                if line.hasPrefix("Hardware Port:") { port = line.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("Device:"), line.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces) == iface, !port.isEmpty {
                    return "\(port) (\(iface))"
                }
            }
        }
        return iface
    }

    static func ownMAC(_ iface: String) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            p = a.pointee.ifa_next
            guard String(cString: a.pointee.ifa_name) == iface, let addr = a.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_LINK) else { continue }
            let raw = UnsafeRawPointer(addr)
            let nlen = Int(raw.load(fromByteOffset: 5, as: UInt8.self)), alen = Int(raw.load(fromByteOffset: 6, as: UInt8.self))
            guard alen == 6 else { continue }
            let bytes = (0..<6).map { raw.load(fromByteOffset: 8 + nlen + $0, as: UInt8.self) }
            return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
        return nil
    }
}

// MARK: ARP cache

enum ARP {
    /// The kernel's ARP table for one interface, read with sysctl (no tool). nil when sysctl failed.
    static func readSysctl(index: UInt32) -> [(ip: String, mac: String)]? {
        // CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO
        var mib: [Int32] = [4, 17, 0, 2, 2, 0x400]
        var len = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0 else { return nil }
        if len == 0 { return [] }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return nil }
        var out: [(String, String)] = []
        var off = 0
        let hdr = 92                                           // sizeof(struct rt_msghdr) on macOS
        while off + hdr + 24 <= len {
            let msglen = Int(buf[off]) | (Int(buf[off + 1]) << 8)
            if msglen < hdr { break }
            let ifIndex = UInt32(buf[off + 4]) | (UInt32(buf[off + 5]) << 8)
            let sin = off + hdr                                // sockaddr_inarp
            let sinLen = Int(buf[sin])
            let sdl = sin + (sinLen > 0 ? (1 + ((sinLen - 1) | 3)) : 4)   // ROUNDUP to 4
            if sdl + 8 <= len, buf[sin + 1] == 2 {
                let nlen = Int(buf[sdl + 5]), alen = Int(buf[sdl + 6])
                if alen == 6, sdl + 8 + nlen + 6 <= len, index == 0 || ifIndex == index {
                    let ip = "\(buf[sin + 4]).\(buf[sin + 5]).\(buf[sin + 6]).\(buf[sin + 7])"
                    let mac = (0..<6).map { String(format: "%02x", buf[sdl + 8 + nlen + $0]) }.joined(separator: ":")
                    out.append((ip, mac))
                }
            }
            off += msglen
        }
        return out
    }

    /// The same table through /usr/sbin/arp -an (fallback, and the independent truth check).
    static func readArpTool(iface: String) -> [(ip: String, mac: String)] {
        guard let t = Sh.run("/usr/sbin/arp", ["-an", "-i", iface]) else { return [] }
        return t.split(separator: "\n").compactMap { ARPText.parse(line: String($0)) }.filter { $0.iface == iface || $0.iface.isEmpty }.map { ($0.ip, $0.mac) }
    }

    static func read(net: NetInfo) -> [(ip: String, mac: String)] {
        let raw = readSysctl(index: net.index) ?? readArpTool(iface: net.iface)
        let own = CIDR.parse(net.ip) ?? 0
        let netAddr = own & net.mask
        var seen = Set<String>(), out: [(String, String)] = []
        for e in raw {
            guard let v = CIDR.parse(e.ip), CIDR.contains(ip: v, net: netAddr, prefix: net.prefix),
                  !CIDR.isBroadcastOrMulticast(v, ownIP: own, prefix: net.prefix),
                  !MAC.isBroadcastOrMulticast(e.mac), !seen.contains(e.ip) else { continue }
            seen.insert(e.ip); out.append(e)
        }
        return out
    }
}

// MARK: sockets

enum Wire {
    static func sockaddr(_ ip: UInt32, port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = ip.bigEndian
        return a
    }

    static func send(_ fd: Int32, _ data: [UInt8], to ip: UInt32, port: UInt16) -> Bool {
        var a = sockaddr(ip, port: port)
        let n = withUnsafePointer(to: &a) { p in
            p.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { sendto(fd, data, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return n >= 0
    }

    static func checksum(_ d: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < d.count { sum += (UInt32(d[i]) << 8) | UInt32(d[i + 1]); i += 2 }
        if i < d.count { sum += UInt32(d[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum & 0xFFFF)
    }

    static func echoRequest(seq: UInt16) -> [UInt8] {
        var p: [UInt8] = [8, 0, 0, 0, 0x4C, 0x53, UInt8(seq >> 8), UInt8(seq & 255), 0x4D, 0x41, 0x4E, 0x54, 0x52, 0x41, 0x21, 0x21]
        let c = checksum(p)
        p[2] = UInt8(c >> 8); p[3] = UInt8(c & 255)
        return p
    }

    /// NetBIOS node-status query for "*": hosts that speak it answer with their name.
    static let nbstat: [UInt8] = {
        var p: [UInt8] = [0x4D, 0x4C, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0x20, 0x43, 0x4B]
        p += [UInt8](repeating: 0x41, count: 30)
        p += [0, 0, 0x21, 0, 1]
        return p
    }()

    /// The host name inside a node-status reply, nil when it is not one.
    static func nbName(from d: [UInt8]) -> String? {
        guard d.count > 57, d[4] == 0, d[5] == 0 else { return nil }
        let count = Int(d[56])
        var i = 57
        for _ in 0..<count {
            guard i + 18 <= d.count else { break }
            let suffix = d[i + 15], flags = (UInt16(d[i + 16]) << 8) | UInt16(d[i + 17])
            if suffix == 0 && (flags & 0x8000) == 0 {
                let raw = String(decoding: d[i..<(i + 15)], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
                return raw.isEmpty ? nil : raw
            }
            i += 18
        }
        return nil
    }

    static func nonblocking(_ fd: Int32) {
        let fl = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, fl | O_NONBLOCK)
    }

    static func bind(_ fd: Int32, toInterface index: UInt32) {
        var i = index
        _ = setsockopt(fd, IPPROTO_IP, 25 /* IP_BOUND_IF */, &i, socklen_t(MemoryLayout<UInt32>.size))
    }
}

final class Sweep {
    var pinged = Set<UInt32>()
    var nbNames: [UInt32: String] = [:]
    var attempts = 0, failures = 0
    private let icmp: Int32, udp: Int32

    init(ifaceIndex: UInt32) {
        icmp = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        udp = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        for fd in [icmp, udp] where fd >= 0 { Wire.nonblocking(fd); Wire.bind(fd, toInterface: ifaceIndex) }
    }
    deinit { if icmp >= 0 { close(icmp) }; if udp >= 0 { close(udp) } }
    var usable: Bool { icmp >= 0 || udp >= 0 }

    /// Reads whatever has arrived for up to `ms` milliseconds.
    func drain(ms: Int32) {
        var fds: [pollfd] = []
        if icmp >= 0 { fds.append(pollfd(fd: icmp, events: Int16(POLLIN), revents: 0)) }
        if udp >= 0 { fds.append(pollfd(fd: udp, events: Int16(POLLIN), revents: 0)) }
        if fds.isEmpty { return }
        let end = Date().addingTimeInterval(Double(ms) / 1000)
        while true {
            let left = Int32(max(0, end.timeIntervalSinceNow * 1000))
            for i in fds.indices { fds[i].revents = 0 }
            let r = poll(&fds, nfds_t(fds.count), left)
            if r <= 0 { return }
            for f in fds where f.revents & Int16(POLLIN) != 0 { readOne(f.fd) }
            if left == 0 { return }
        }
    }

    private func readOne(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 1500)
        var from = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &from) { fp in
            fp.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
        }
        guard n > 0 else { return }
        let src = UInt32(bigEndian: from.sin_addr.s_addr)
        if fd == icmp {
            let ihl = (buf[0] >> 4) == 4 ? Int(buf[0] & 0x0F) * 4 : 0
            if ihl < n, buf[ihl] == 0 { pinged.insert(src) }          // echo reply
        } else if let name = Wire.nbName(from: Array(buf[0..<n])) {
            nbNames[src] = name
        }
    }

    /// Probes the hosts in batches; `progress` gets 0...1 of this pass; `cancelled` stops it.
    func pass(_ hosts: [UInt32], tail: Int32, progress: (Double) -> Void, cancelled: () -> Bool) {
        var seq: UInt16 = 1
        let batch = 64
        var i = 0
        while i < hosts.count {
            if cancelled() { return }
            for h in hosts[i..<min(hosts.count, i + batch)] {
                if icmp >= 0 {
                    attempts += 1
                    if !Wire.send(icmp, Wire.echoRequest(seq: seq), to: h, port: 0) { failures += 1 }
                    seq &+= 1
                }
                if udp >= 0 { _ = Wire.send(udp, Wire.nbstat, to: h, port: 137) }
            }
            drain(ms: 60)
            i += batch
            progress(Double(min(i, hosts.count)) / Double(max(1, hosts.count)) * 0.8)
        }
        drain(ms: tail)
        progress(1)
    }
}

// MARK: names

enum Names {
    static func reverseDNS(_ ip: String) -> String? {
        guard let v = CIDR.parse(ip) else { return nil }
        var a = Wire.sockaddr(v, port: 0)
        var host = [CChar](repeating: 0, count: 256)
        let r = withUnsafePointer(to: &a) { p in
            p.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, 256, nil, 0, NI_NAMEREQD)
            }
        }
        guard r == 0 else { return nil }
        let full = String(cString: host)
        if full.isEmpty || CIDR.parse(full) != nil { return nil }
        return shorten(full)
    }

    /// "printer.lan" -> "printer", "mac-mini.local." -> "mac-mini".
    static func shorten(_ host: String) -> String {
        var h = host
        if h.hasSuffix(".") { h.removeLast() }
        let first = h.split(separator: ".").first.map(String.init) ?? h
        return first
    }

    static func looksLikeHash(_ s: String) -> Bool {
        let hex = s.filter { $0.isHexDigit }.count
        return s.count >= 16 && hex * 10 >= s.count * 8
    }

    /// Reverse DNS for every address in parallel, one overall deadline.
    static func reverseAll(_ ips: [String], deadline: Double = 3) -> [String: String] {
        var out: [String: String] = [:]
        let lock = NSLock()
        let g = DispatchGroup()
        for ip in ips {
            g.enter()
            DispatchQueue.global(qos: .utility).async {
                if let n = reverseDNS(ip) { lock.lock(); out[ip] = n; lock.unlock() }
                g.leave()
            }
        }
        _ = g.wait(timeout: .now() + deadline)
        lock.lock(); defer { lock.unlock() }
        return out
    }
}

// MARK: Bonjour

struct BonjourInfo { var name = ""; var friendly = ""; var host = ""; var services = Set<String>(); var model = "" }

/// Browses a fixed list of service types (NSBonjourServices lists the same) and resolves what it finds.
/// All delegate calls arrive on the main run loop; `results()` is read from another thread.
final class Bonjour: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let types = ["_airplay._tcp", "_raop._tcp", "_googlecast._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
                        "_scanner._tcp", "_uscan._tcp", "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_http._tcp", "_https._tcp",
                        "_companion-link._tcp", "_homekit._tcp", "_hap._tcp", "_spotify-connect._tcp", "_sleep-proxy._udp",
                        "_device-info._tcp", "_workstation._tcp", "_rfb._tcp", "_eppc._tcp", "_adisk._tcp", "_hue._tcp", "_matter._tcp",
                        "_matterc._udp", "_meshcop._udp", "_androidtvremote2._tcp", "_amzn-wplay._tcp", "_mediaremotetv._tcp",
                        "_nvstream._tcp", "_daap._tcp", "_touch-able._tcp", "_nfs._tcp"]
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var info: [String: BonjourInfo] = [:]

    func start() {
        for t in Bonjour.types {
            let b = NetServiceBrowser()
            b.delegate = self
            b.searchForServices(ofType: t + ".", inDomain: "local.")
            browsers.append(b)
        }
    }

    func stop() {
        browsers.forEach { $0.stop() }
        services.forEach { $0.stop() }
        browsers = []; services = []
    }

    func results() -> [String: BonjourInfo] {
        if Thread.isMainThread { return info }
        return DispatchQueue.main.sync { info }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let type = sender.type.hasSuffix(".") ? String(sender.type.dropLast()) : sender.type
        var model = "", friendly = ""
        if let d = sender.txtRecordData() {
            let t = NetService.dictionary(fromTXTRecord: d)
            if let m = t["model"] { model = String(decoding: m, as: UTF8.self) }
            if let f = t["fn"] { friendly = String(decoding: f, as: UTF8.self) }
        }
        var host = sender.hostName ?? ""
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasSuffix(".local") { host = String(host.dropLast(6)) }
        var sname = sender.name
        if let at = sname.firstIndex(of: "@"), sname[..<at].allSatisfy({ $0.isHexDigit }) { sname = String(sname[sname.index(after: at)...]) }
        for data in sender.addresses ?? [] {
            guard data.count >= MemoryLayout<sockaddr_in>.size else { continue }
            let ok = data.withUnsafeBytes { raw -> String? in
                let sa = raw.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                guard sa.sin_family == sa_family_t(AF_INET) else { return nil }
                return CIDR.string(UInt32(bigEndian: sa.sin_addr.s_addr))
            }
            guard let ip = ok else { continue }
            var e = info[ip] ?? BonjourInfo()
            e.services.insert(type)
            if e.model.isEmpty { e.model = model }
            if e.friendly.isEmpty { e.friendly = friendly }
            if e.host.isEmpty, !host.isEmpty, !Names.looksLikeHash(host) { e.host = host }
            if e.name.isEmpty || type == "_device-info._tcp" { e.name = sname }
            info[ip] = e
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}
}

// MARK: the scan

enum LanScanner {
    static func scan(net: NetInfo?, bonjour: Bonjour?, progress: @escaping (Double, String) -> Void, cancelled: @escaping () -> Bool) -> ScanResult {
        var res = ScanResult()
        guard let net = net else {
            res.error = "No network: this Mac has no active IPv4 network."
            return res
        }
        res.net = net
        guard let own = CIDR.parse(net.ip) else { res.error = "Cannot read this Mac's address."; return res }
        let plan = CIDR.hosts(ip: own, prefix: net.prefix)
        res.capped = plan.capped
        res.cidr = CIDR.network(ip: own, prefix: net.prefix)
        if plan.capped {
            res.notes.append("The network is \(res.cidr), too wide: scanned only the /22 around this Mac (\(CIDR.network(ip: own, prefix: plan.scannedPrefix))).")
        }
        if plan.hosts.isEmpty { res.error = "Nothing to scan on \(net.iface)."; return res }
        if net.gateway == nil { res.notes.append("No router found for \(net.iface).") }

        let started = Date()
        let sweep = Sweep(ifaceIndex: net.index)
        guard sweep.usable else { res.error = "Cannot open the network sockets."; return res }
        progress(0.02, "Sweeping \(plan.hosts.count) addresses")
        sweep.pass(plan.hosts, tail: 1000, progress: { progress(0.02 + $0 * 0.62, "Sweeping \(plan.hosts.count) addresses") }, cancelled: cancelled)
        if cancelled() { res.error = "Stopped."; return res }
        var arp = ARP.read(net: net)
        let have = Set(arp.compactMap { CIDR.parse($0.ip) }).union(sweep.pinged)
        let missing = plan.hosts.filter { !have.contains($0) }
        if !missing.isEmpty && missing.count < plan.hosts.count {
            progress(0.66, "Second look at \(missing.count) quiet addresses")
            sweep.pass(missing, tail: 600, progress: { progress(0.66 + $0 * 0.14, "Second look at \(missing.count) quiet addresses") }, cancelled: cancelled)
            arp = ARP.read(net: net)
        }
        if cancelled() { res.error = "Stopped."; return res }

        // permission: every send refused, or not even the router answered
        let gwV = net.gateway.flatMap { CIDR.parse($0) }
        let gwSeen = gwV.map { g in sweep.pinged.contains(g) || arp.contains { CIDR.parse($0.ip) == g } } ?? true
        if (sweep.attempts > 0 && sweep.failures == sweep.attempts) || (!gwSeen && sweep.pinged.isEmpty && arp.isEmpty) {
            res.permissionSuspect = true
            res.error = "Cannot reach the network. Local Network access is probably off for this app: click PERMISSIONS and switch it on."
        }

        progress(0.82, "Reading names")
        // devices: the ARP cache plus anyone who answered the ping
        var byIP: [UInt32: Device] = [:]
        for e in arp {
            guard let v = CIDR.parse(e.ip), v != own else { continue }
            var d = Device(ip: e.ip, mac: e.mac)
            d.answeredPing = sweep.pinged.contains(v)
            byIP[v] = d
        }
        for v in sweep.pinged where v != own && byIP[v] == nil && CIDR.contains(ip: v, net: own, prefix: net.prefix) {
            var d = Device(ip: CIDR.string(v), mac: "")
            d.answeredPing = true
            byIP[v] = d
        }
        // this Mac
        var me = Device(ip: net.ip, mac: Net.ownMAC(net.iface) ?? "")
        me.isThisMac = true
        me.name = Host.current().localizedName ?? Names.shorten(ProcessInfo.processInfo.hostName)
        byIP[own] = me

        // names: Bonjour first, then reverse DNS, then NetBIOS
        let remaining = max(0, 4.2 - Date().timeIntervalSince(started))
        if remaining > 0 && !cancelled() { Thread.sleep(forTimeInterval: min(remaining, 2.5)) }   // let Bonjour answers arrive
        let bj = bonjour?.results() ?? [:]
        let others = byIP.keys.filter { $0 != own }.map { CIDR.string($0) }
        let rdns = Names.reverseAll(others)
        progress(0.95, "Naming")
        for (v, var d) in byIP {
            let ip = CIDR.string(v)
            if let b = bj[ip] {
                d.services = Array(b.services).sorted()
                d.model = b.model
                if !b.friendly.isEmpty { d.name = b.friendly }
                else if !b.host.isEmpty { d.name = b.host }
                else if !b.name.isEmpty { d.name = b.name }
            }
            if d.name.isEmpty, let n = rdns[ip] { d.name = n }
            if d.name.isEmpty, let n = sweep.nbNames[v] { d.name = n }
            if !d.isThisMac { d.isRouter = (ip == net.gateway) }
            if d.isThisMac { d.isRouter = false }
            d.maker = d.mac.isEmpty ? "" : OUI.lookup(mac: d.mac)
            d.kind = Kinds.guess(device: d)
            d.seen = Date()
            byIP[v] = d
        }
        res.devices = byIP.keys.sorted().compactMap { byIP[$0] }
        progress(1, "Done")
        return res
    }
}
