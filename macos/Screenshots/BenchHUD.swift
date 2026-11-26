// Plays the real panel animations (open, page, ⌘K, close) and prints frame intervals per step.
// Used by CI to compare builds; not part of the app.
// NIMBUS_BENCH_REFRESH=old repeats what the app's 1 s refresh used to do on the main thread
// (pgrep/route subprocesses, re-publishing every model value); "new" publishes nothing that didn't change.
import AppKit
import QuartzCore
import SwiftUI

struct Strategy {
    let id: String
    let name: String
}

final class FrameMeter: NSObject {
    private(set) var order: [String] = []
    private(set) var samples: [String: [Double]] = [:]
    private var phase = ""
    private var last: CFTimeInterval = 0
    private var link: CADisplayLink?
    private(set) var refresh: Double = 60

    func start(on screen: NSScreen) {
        refresh = Double(screen.maximumFramesPerSecond)
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() { link?.invalidate() }

    private(set) var busy: [String: [Double]] = [:]
    private var turnStart: CFAbsoluteTime = 0
    private var observer: CFRunLoopObserver?

    /// How long the main thread works per run loop turn: a long turn is a visible hitch whatever the display rate.
    func watchRunLoop() {
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [unowned self] _, activity in
            let now = CFAbsoluteTimeGetCurrent()
            if activity == .afterWaiting {
                turnStart = now
            } else if turnStart > 0, !phase.isEmpty {
                busy[phase, default: []].append((now - turnStart) * 1000)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        observer = obs
    }

    func begin(_ name: String) {
        phase = name
        if samples[name] == nil {
            samples[name] = []
            order.append(name)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = link.timestamp
        if last > 0, !phase.isEmpty { samples[phase, default: []].append((t - last) * 1000) }
        last = t
    }
}

@main
struct BenchHUD {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: .darkAqua)
        let refreshMode = ProcessInfo.processInfo.environment["NIMBUS_BENCH_REFRESH"] ?? "new"

        let model = HUDModel()
        let strategies = (0..<6).map { Strategy(id: "s\($0)", name: "general (ALT\($0))") }
        model.strategies = strategies
        model.selectedStrategyID = "s3"
        model.strategyName = "general (ALT3)"
        model.running = true
        model.discord = .ok
        model.youtube = .ok
        model.discordMs = 42
        model.youtubeMs = 118
        model.latencySamples = (0..<40).map { 55 + Double(($0 * 7) % 13) }
        model.engineStarted = Date().addingTimeInterval(-8076)
        model.networkInterface = "en0"
        model.networkAddress = "192.168.1.24"
        model.versionTitle = "Версия 1.6.0"

        let controller = HUDController(model: model)
        if ProcessInfo.processInfo.environment["NIMBUS_BENCH"] == "build" {
            buildCosts(model)
            return
        }
        #if PREWARM
        controller.prewarm()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        #endif
        guard let screen = NSScreen.main else { print("no screen"); exit(1) }
        let visible = screen.visibleFrame
        let anchor = NSRect(x: visible.midX - 12, y: visible.maxY, width: 24, height: 24)
        NSApp.activate(ignoringOtherApps: true)

        var tick = 0
        let refresh = Timer(timeInterval: 1, repeats: true) { _ in
            tick += 1
            guard refreshMode == "old" else { return }
            for _ in 0..<3 { run("/usr/bin/pgrep", ["-x", "utunws"]) }
            if tick % 4 == 0 { run("/sbin/route", ["-n", "get", "default"]) }
            // every assignment fires objectWillChange, equal value or not
            model.running = model.running
            model.busy = model.busy
            model.testing = model.testing
            model.strategies = model.strategies
            model.strategyName = model.strategyName
            model.selectedStrategyID = model.selectedStrategyID
            model.ipsetMode = model.ipsetMode
            model.loginEnabled = model.loginEnabled
            model.versionTitle = model.versionTitle
            model.testTitle = model.testTitle
            model.testRows = model.testRows
            model.discord = model.discord
            model.youtube = model.youtube
            model.autoPauseVpn = model.autoPauseVpn
            model.vpnWarning = model.vpnWarning
        }
        RunLoop.main.add(refresh, forMode: .common)

        let meter = FrameMeter()
        meter.start(on: screen)
        meter.watchRunLoop()
        var resizes: [String: [Double]] = [:]
        var resizePhase = ""
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: controller.window, queue: .main) { n in
            if let w = n.object as? NSWindow { resizes[resizePhase, default: []].append(Double(w.frame.height)) }
        }
        func step(_ name: String, _ seconds: Double, _ action: () -> Void) {
            meter.begin(name)
            resizePhase = name
            action()
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        step("open", 1.2) { controller.show(below: anchor, on: screen) }
        for i in 0..<5 {
            step(i == 0 ? "page-more (1st)" : "page-more", 0.9) { withAnimation(Motion.smooth) { model.page = .more } }
            step("page-back", 0.9) { withAnimation(Motion.smooth) { model.page = .main } }
        }
        for page in [HUDPage.lists, .logs, .diagnostics] {
            step("page-\(page.rawValue)", 0.9) { withAnimation(Motion.smooth) { model.page = page } }
            step("page-back", 0.9) { withAnimation(Motion.smooth) { model.page = .main } }
        }
        step("palette-open", 0.8) { model.openPalette() }
        step("palette-close", 0.6) { model.closePalette() }
        step("idle", 2.0) {}
        step("close", 0.6) { controller.close() }
        meter.stop()

        print("refresh=\(refreshMode) display=\(Int(meter.refresh)) Hz")
        print("step            frames  avg ms  p95 ms  max ms  long")
        let budget = 1000 / meter.refresh * 1.5
        for name in meter.order {
            let list = meter.samples[name] ?? []
            guard !list.isEmpty else { print(name.padding(toLength: 15, withPad: " ", startingAt: 0) + " 0"); continue }
            let sorted = list.sorted()
            let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
            let avg = list.reduce(0, +) / Double(list.count)
            let long = list.filter { $0 > budget }.count
            print(name.padding(toLength: 15, withPad: " ", startingAt: 0)
                  + String(format: " %6d  %6.1f  %6.1f  %6.1f  %4d", list.count, avg, p95, sorted.last!, long))
        }
        print("window resizes per phase (heights):")
        for name in meter.order {
            guard let list = resizes[name], !list.isEmpty else { continue }
            print("  \(name): \(list.count)  " + list.prefix(14).map { String(Int($0)) }.joined(separator: " "))
        }
        print("main-thread turns (ms)  turns  total   p95    max   >16ms")
        for name in meter.order {
            let list = (meter.busy[name] ?? []).sorted()
            guard !list.isEmpty else { continue }
            let p95 = list[min(list.count - 1, Int((Double(list.count) * 0.95).rounded(.up)) - 1)]
            print(name.padding(toLength: 22, withPad: " ", startingAt: 0)
                  + String(format: " %5d  %6.0f  %5.1f  %5.1f  %5d", list.count, list.reduce(0, +), p95, list.last!, list.filter { $0 > 16 }.count))
        }
    }

    /// How long a page takes to build and lay out in a fresh hosting view (no window, no rendering).
    static func buildCosts(_ model: HUDModel) {
        var pages: [(String, () -> AnyView)] = [("main", { AnyView(MainPage(model: model)) })]
        #if EAGER
        pages.append(("more (all)", { AnyView(MorePage(model: model, eager: true)) }))
        pages.append(("more (1st turn)", { AnyView(MorePage(model: model)) }))
        #else
        pages.append(("more", { AnyView(MorePage(model: model)) }))
        #endif
        pages += [
            ("lists", { AnyView(ListsPage(model: model)) }),
            ("logs", { AnyView(LogsPage(model: model)) }),
            ("diagnostics", { AnyView(DiagnosticsPage(model: model)) }),
            ("editor", { AnyView(EditorPage(model: model)) }),
        ]
        // cost of single components, 20 of each in a stack
        struct Parts: View {
            @ObservedObject var model: HUDModel
            let kind: String
            @State var text = ""
            var body: some View {
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in
                        switch kind {
                        case "text": Text("Строка \(i)").font(NB.body)
                        case "icon": RowIcon(name: "bolt")
                        case "keycap": Keycap("⌘", "K")
                        case "meta": MetaText(text: "21 стратегий")
                        case "row": ActionRow(icon: "bolt", title: "Подобрать", action: {}) { Keycap("⌘", "F") }
                        case "rowplain": ActionRow(icon: "bolt", title: "Подобрать", action: {}) { EmptyView() }
                        case "input": PanelInput(placeholder: "Поиск", text: $text, trailing: { EmptyView() })
                        case "switch": SwitchRow(icon: "bolt", title: "Параметр", isOn: i % 2 == 0, action: {})
                        case "reveal": Text("Строка \(i)").reveal(i)
                        case "label": SectionLabel(title: "Действия")
                        default: EmptyView()
                        }
                    }
                }
            }
        }
        print("20 of each component, ms to build + lay out (1st … 4th)")
        for kind in ["text", "icon", "keycap", "meta", "rowplain", "row", "input", "switch", "reveal", "label"] {
            var times: [Double] = []
            for _ in 0..<4 {
                let t0 = CFAbsoluteTimeGetCurrent()
                let host = NSHostingView(rootView: Parts(model: model, kind: kind).frame(width: NB.width).fixedSize(horizontal: false, vertical: true))
                host.frame = NSRect(x: 0, y: 0, width: NB.width, height: 1200)
                host.layoutSubtreeIfNeeded()
                times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            print(kind.padding(toLength: 12, withPad: " ", startingAt: 0) + times.map { String(format: "%6.1f", $0) }.joined(separator: " "))
        }
        print("page build + layout, ms per fresh view (1st … 6th)")
        for (name, make) in pages {
            var times: [Double] = []
            for _ in 0..<6 {
                let t0 = CFAbsoluteTimeGetCurrent()
                let host = NSHostingView(rootView: make().frame(width: NB.width).fixedSize(horizontal: false, vertical: true))
                host.frame = NSRect(x: 0, y: 0, width: NB.width, height: 800)
                host.layoutSubtreeIfNeeded()
                times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            print(name.padding(toLength: 12, withPad: " ", startingAt: 0) + times.map { String(format: "%6.1f", $0) }.joined(separator: " "))
        }
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
