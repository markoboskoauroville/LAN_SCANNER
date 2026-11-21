// LAN Scanner (Mantra): every device on the network this Mac is on now. One window, one action: SCAN.
// Entry point, the window, the headless modes (--json, --selftest, --studio-shot <png>).
import Cocoa
import SwiftUI

let VERSION = 3
let APP_NAME = "LAN Scanner (Mantra)"
enum Debug { static var forcePermission = false }
let LOCAL_NETWORK_PANE = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"

// MARK: look (Mantra design language ground: dark, warm ink, monospace; amber for what needs the person)

enum Look {
    static let ground = Color(red: 0.043, green: 0.051, blue: 0.063)      // #0B0D10
    static let ink = Color(red: 0.949, green: 0.867, blue: 0.706)         // #F2DDB4
    static let dim = Color(red: 0.949, green: 0.867, blue: 0.706).opacity(0.55)
    static let amber = Color(red: 0.91, green: 0.639, blue: 0.239)        // #E8A33D
    static let line = Color(red: 0.949, green: 0.867, blue: 0.706).opacity(0.18)
    static func mono(_ s: CGFloat, bold: Bool = false) -> Font { .system(size: s, weight: bold ? .bold : .regular, design: .monospaced) }
}

final class Flag { private let l = NSLock(); private var v = false
    var value: Bool { get { l.lock(); defer { l.unlock() }; return v } set { l.lock(); v = newValue; l.unlock() } } }

// MARK: state

@MainActor
final class ScanState: ObservableObject {
    @Published var devices: [Device] = []
    @Published var gone: [Device] = []
    @Published var running = false
    @Published var progress = 0.0
    @Published var phase = ""
    @Published var error: String? = nil
    @Published var notes: [String] = []
    @Published var permissionSuspect = false
    @Published var net: NetInfo? = nil
    @Published var cidr = ""
    @Published var others: [NetInfo] = []
    @Published var scanned: Date? = nil
    @Published var copied = ""
    var chosenIface: String? = nil
    private let cancel = Flag()
    private var bonjour: Bonjour?

    func scan() {
        guard !running else { return }
        running = true; progress = 0; phase = "Starting"; cancel.value = false; error = nil; copied = ""
        if let fx = Fixture.current, let step = Fixture.next() {
            net = step.net.map { Fixture.info($0) }
            others = (fx.others ?? []).map { Fixture.info($0) }
            let flag = cancel
            DispatchQueue.global(qos: .userInitiated).async {
                var r = Fixture.result(step, progress: { p, s in DispatchQueue.main.async { self.progress = p; self.phase = s } }, cancelled: { flag.value })
                if Debug.forcePermission { r.permissionSuspect = true; r.error = "Cannot reach the network. Local Network access is probably off for this app: click PERMISSIONS and switch it on." }
                DispatchQueue.main.async { self.finish(r) }
            }
            return
        }
        let list = Net.activeInterfaces()
        let chosen = chosenIface.flatMap { n in list.first { $0.iface == n } } ?? Net.current(from: list)
        net = chosen
        others = list.filter { $0.iface != chosen?.iface }
        let bj = Bonjour(); bonjour = bj; bj.start()
        let flag = cancel
        DispatchQueue.global(qos: .userInitiated).async {
            let r = LanScanner.scan(net: chosen, bonjour: bj, progress: { p, s in
                DispatchQueue.main.async { self.progress = p; self.phase = s }
            }, cancelled: { flag.value })
            DispatchQueue.main.async { bj.stop(); var r = r
                if Debug.forcePermission { r.permissionSuspect = true; r.error = "Cannot reach the network. Local Network access is probably off for this app: click PERMISSIONS and switch it on." }
                self.finish(r) }
        }
    }

    func stop() { cancel.value = true; phase = "Stopping" }

    private func finish(_ r: ScanResult) {
        running = false
        error = r.error; notes = r.notes; permissionSuspect = r.permissionSuspect; cidr = r.cidr
        if r.error == "Stopped." { return }
        gone = Merge.gone(previous: devices, current: r.devices, alreadyGone: gone)
        devices = r.devices
        scanned = Date()
    }

    func copy(_ d: Device) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(d.ip, forType: .string)
        copied = "Copied \(d.ip)"
    }

    func pick(_ n: NetInfo) { chosenIface = n.iface; scan() }

    func openPermissions() {
        if let u = URL(string: LOCAL_NETWORK_PANE) { NSWorkspace.shared.open(u) }
    }

    var header: String {
        guard let n = net else { return "" }
        var s = "\(n.title)  ·  this Mac \(n.ip)  ·  \(cidr.isEmpty ? CIDR.network(ip: CIDR.parse(n.ip) ?? 0, prefix: n.prefix) : cidr)"
        s += "  ·  router \(n.gateway ?? "none")"
        s += "  ·  \(devices.count) device\(devices.count == 1 ? "" : "s")"
        return s
    }
}

// MARK: view

struct HoverWord: View {
    var size: CGFloat = 15
    var bold = true
    let text: String; let color: Color; let id: String; let label: String; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(text).font(Look.mono(size, bold: bold)).foregroundColor(color).underline(hover)
                .padding(.vertical, 6).padding(.horizontal, 2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hover = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityIdentifier(id).accessibilityLabel(label)
    }
}

struct Hairline: View { var body: some View { Rectangle().fill(Look.line).frame(height: 1) } }

struct Cell: View {
    let text: String; let width: CGFloat?; var color: Color = Look.ink
    var body: some View {
        let t = Text(text.isEmpty ? " " : text).font(Look.mono(12)).foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true).lineLimit(3)
        if let w = width { t.frame(width: w, alignment: .leading) } else { t.frame(maxWidth: .infinity, alignment: .leading) }
    }
}

struct Columns {
    static let ip: CGFloat = 112, mac: CGFloat = 136, maker: CGFloat = 120, kind: CGFloat = 78, seen: CGFloat = 84
}

struct Row: View {
    let d: Device; let state: ScanState
    static let g: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    var body: some View {
        let c = d.gone ? Look.dim : Look.ink
        let label = d.isThisMac ? "This Mac" : d.isRouter ? "Router" : ""
        let base = d.displayName
        let name = label.isEmpty ? base : (d.name.isEmpty ? label : "\(d.name) (\(label))")
        let seen = d.gone ? "gone \(Row.g.string(from: d.seen))" : Row.f.string(from: d.seen)
        Button { state.copy(d) } label: {
            HStack(alignment: .top, spacing: 12) {
                Cell(text: name, width: nil, color: d.name.isEmpty ? Look.dim : c)
                Cell(text: d.ip, width: Columns.ip, color: c)
                Cell(text: d.mac, width: Columns.mac, color: c)
                Cell(text: d.maker, width: Columns.maker, color: c)
                Cell(text: d.kind, width: Columns.kind, color: c)
                Cell(text: seen, width: Columns.seen, color: Look.dim)
            }
            .padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { state.copy(d) }
        .accessibilityIdentifier("row-\(d.ip)")
        .accessibilityLabel("\(name), \(d.ip), \(d.mac), \(d.maker), \(d.kind), \(seen)")
    }
}

struct MainView: View {
    @ObservedObject var state: ScanState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // top row: the title once, the version, PERMISSIONS only while one is missing
            HStack(spacing: 10) {
                Text(APP_NAME).font(Look.mono(15, bold: true)).foregroundColor(Look.ink)
                Text("v\(VERSION)").font(Look.mono(11)).foregroundColor(Look.dim)
                    .accessibilityIdentifier("version").accessibilityLabel("version \(VERSION)")
                Spacer()
                if state.permissionSuspect {
                    HoverWord(text: "PERMISSIONS", color: Look.amber, id: "permissions", label: "PERMISSIONS") { state.openPermissions() }
                }
            }
            .padding(.top, 34).padding(.bottom, 10)
            Hairline()
            // the one action
            HStack(spacing: 14) {
                HoverWord(text: state.running ? "STOP  \(Int(state.progress * 100)) %" : "SCAN", color: Look.ink,
                          id: state.running ? "stop" : "scan", label: state.running ? "STOP" : "SCAN") {
                    if state.running { state.stop() } else { state.scan() }
                }
                Text(state.running ? state.phase : (state.copied.isEmpty ? "" : state.copied)).font(Look.mono(12)).foregroundColor(Look.dim)
                Spacer()
            }
            .padding(.vertical, 4)
            Hairline()
            // the network
            if state.net != nil {
                Text(state.header).font(Look.mono(12)).foregroundColor(Look.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    .accessibilityIdentifier("network").accessibilityLabel(state.header)
            }
            ForEach(state.others, id: \.iface) { n in
                HoverWord(size: 12, bold: false, text: "OTHER NETWORK \(n.iface)  \(n.ip)/\(n.prefix)", color: Look.dim, id: "net-\(n.iface)", label: "scan \(n.iface)") { state.pick(n) }
            }
            ForEach(state.notes, id: \.self) { Text($0).font(Look.mono(12)).foregroundColor(Look.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 4) }
            if let e = state.error {
                Text(e).font(Look.mono(12, bold: true)).foregroundColor(Look.amber).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    .accessibilityIdentifier("error").accessibilityLabel(e)
            }
            if state.running { Rectangle().fill(Look.ink.opacity(0.7)).frame(height: 1).scaleEffect(x: max(0.001, state.progress), y: 1, anchor: .leading).padding(.top, 8) }
            // the table
            HStack(alignment: .top, spacing: 12) {
                Cell(text: "NAME", width: nil, color: Look.dim); Cell(text: "IP", width: Columns.ip, color: Look.dim)
                Cell(text: "MAC", width: Columns.mac, color: Look.dim); Cell(text: "MAKER", width: Columns.maker, color: Look.dim)
                Cell(text: "KIND", width: Columns.kind, color: Look.dim); Cell(text: "SEEN", width: Columns.seen, color: Look.dim)
            }.padding(.top, 14).padding(.bottom, 4)
            Hairline()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(state.devices + state.gone, id: \.ip) { d in Row(d: d, state: state); Hairline().opacity(0.4) }
                    if state.devices.isEmpty && !state.running && state.error == nil && state.scanned != nil {
                        Text("No devices found.").font(Look.mono(12)).foregroundColor(Look.dim).padding(.top, 10)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity, alignment: .topLeading)
        .background(Look.ground)
        .focusEffectDisabled()
    }
}

// MARK: app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = ScanState()
    var window: NSWindow?
    static let minContent = NSSize(width: 780, height: 360)

    func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = APP_NAME
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.backgroundColor = NSColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1)
        let host = NSHostingView(rootView: MainView(state: state))
        host.sizingOptions = []
        w.contentView = host
        w.contentMinSize = Self.minContent   // after the content view is set, or it is reset
        w.setFrameAutosaveName("LanScannerMainWindow")
        w.delegate = self
        window = w
        return w
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let w = makeWindow()
        if !w.setFrameUsingName("LanScannerMainWindow") { w.center() }
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(nil)                      // nothing is focused at launch: no focus ring
        enforceOneTitle()
        DispatchQueue.main.async { w.makeFirstResponder(nil); self.enforceOneTitle() }
        state.scan()                                   // a scan runs once when the window opens
        Updater.checkAtStart()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }   // the X quits the app

    func enforceOneTitle() {
        guard let w = window else { return }
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        if let frame = w.contentView?.superview { hideTitleEcho(in: frame, title: w.title, skip: w.contentView) }
    }
    private func hideTitleEcho(in v: NSView, title: String, skip: NSView?) {
        for s in v.subviews where s !== skip {
            if let t = s as? NSTextField, t.stringValue == title { t.isHidden = true }
            hideTitleEcho(in: s, title: title, skip: skip)
        }
    }
    func windowDidBecomeKey(_ notification: Notification) { enforceOneTitle() }
    func windowDidResignKey(_ notification: Notification) { enforceOneTitle() }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let m = sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minContent)).size   // nothing is ever cut: below this size the table would be
        return NSSize(width: max(frameSize.width, m.width), height: max(frameSize.height, m.height))
    }
    func windowDidResize(_ notification: Notification) {
        if let w = window, w.contentLayoutRect.width < Self.minContent.width - 0.5 || w.contentLayoutRect.height < Self.minContent.height - 0.5 {
            w.setContentSize(NSSize(width: max(w.contentLayoutRect.width, Self.minContent.width), height: max(w.contentLayoutRect.height, Self.minContent.height)))
        }
        enforceOneTitle()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { enforceOneTitle() }
    func windowDidExitFullScreen(_ notification: Notification) { enforceOneTitle() }
}

// MARK: headless

enum Headless {
    static func json(iface: String?) -> Never {
        let bj = Bonjour()
        DispatchQueue.main.async { bj.start() }
        DispatchQueue.global().async {
            let list = Net.activeInterfaces()
            let net = iface.flatMap { n in list.first { $0.iface == n } } ?? Net.current(from: list)
            let r = LanScanner.scan(net: net, bonjour: bj, progress: { _, _ in }, cancelled: { false })
            var o: [String: Any] = [
                "version": VERSION,
                "network": r.net?.title ?? "", "interface": r.net?.iface ?? "", "ip": r.net?.ip ?? "",
                "cidr": r.cidr, "gateway": r.net?.gateway ?? "", "deviceCount": r.devices.count,
                "notes": r.notes, "permissionSuspect": r.permissionSuspect,
                "devices": r.devices.map { ["ip": $0.ip, "mac": $0.mac, "name": $0.name, "label": $0.displayName, "maker": $0.maker, "kind": $0.kind] },
            ]
            if let e = r.error { o["error"] = e }
            if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(d); FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exit(r.error == nil ? 0 : 2)
        }
        RunLoop.main.run()
        exit(0)
    }
}

@main
struct Entry {
    static func main() {
        let a = CommandLine.arguments
        if a.contains("--selftest") { exit(SelfTest.run() ? 0 : 1) }
        if a.contains("--version") { print(VERSION); exit(0) }
        if a.contains("--debug-permission") { Debug.forcePermission = true }
        if let i = a.firstIndex(of: "--fixture"), i + 1 < a.count {
            guard let f = Fixture.load(a[i + 1]) else { print("cannot read fixture \(a[i + 1])"); exit(4) }
            Fixture.current = f
        }
        if a.contains("--json") {
            let i = a.firstIndex(of: "--iface").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
            Headless.json(iface: i)
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            if let i = a.firstIndex(of: "--studio-shot"), i + 1 < a.count {
                app.setActivationPolicy(.accessory)
                StudioShot.run(delegate: delegate, path: a[i + 1], width: a.firstIndex(of: "--width").flatMap { Int(a[$0 + 1]) } ?? 920)
            } else {
                app.setActivationPolicy(.regular)
            }
            app.run()
        }
    }
}

/// --studio-shot <png> [--width N]: scans, renders the window's content off screen into a PNG, exits.
@MainActor
enum StudioShot {
    static func run(delegate: AppDelegate, path: String, width: Int) {
        let w = delegate.makeWindow()
        w.setFrame(NSRect(x: -30000, y: -30000, width: CGFloat(width), height: 560), display: false)
        w.orderBack(nil)
        delegate.state.scan()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
            MainActor.assumeIsolated {
                guard !delegate.state.running, delegate.state.scanned != nil || delegate.state.error != nil else { return }
                t.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    MainActor.assumeIsolated {
                        guard let v = w.contentView else { exit(3) }
                        v.layoutSubtreeIfNeeded()
                        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(3) }
                        v.cacheDisplay(in: v.bounds, to: rep)
                        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
                        print("studio-shot written: \(path)")
                        exit(0)
                    }
                }
            }
        }
    }
}
