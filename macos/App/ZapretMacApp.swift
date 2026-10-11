import AppKit
import Combine
import CryptoKit
import Foundation
import Security
import SwiftUI

@_silgen_name("AuthorizationExecuteWithPrivileges")
private func executeWithPrivileges(
    _ authorization: AuthorizationRef,
    _ path: UnsafePointer<CChar>,
    _ flags: AuthorizationFlags,
    _ arguments: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>,
    _ pipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>
) -> OSStatus

struct Strategy: Identifiable, Hashable {
    let id: String
    let name: String
}

struct StrategyTestRow: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let score: String
    let detail: String
}

enum PopoverScreen: Hashable {
    case home
    case test
    case domains
    case more
}

enum Reachability: Equatable {
    case unchecked
    case checking
    case up
    case down

    var title: String {
        switch self {
        case .unchecked: return "не проверено"
        case .checking: return "проверка"
        case .up: return "доступен"
        case .down: return "нет"
        }
    }
}

private enum MenuGlyph {
    case off
    case running
    case working
    case update
    case failed
}

struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let downloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }
}

enum ZapretTheme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.06)
    static let accent = Color(red: 0.83, green: 0.55, blue: 0.22)
    static let accentLift = Color(red: 0.90, green: 0.66, blue: 0.34)
    static let running = Color(red: 82.0 / 255.0, green: 204.0 / 255.0, blue: 132.0 / 255.0)
    static let popoverWidth: CGFloat = 640
    static let popoverHeight: CGFloat = 460
    static let narrowWidth: CGFloat = 360
    static let popoverRadius: CGFloat = 22
    static let cardRadius: CGFloat = 18
    static let rowRadius: CGFloat = 16
    static let insetFill = Color.white.opacity(0.06)
    static let softFill = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.10)
    static let pillSelected = Color(red: 0.83, green: 0.55, blue: 0.22).opacity(0.22)
    static let text = Color(red: 0.91, green: 0.89, blue: 0.84)
    static let secondary = Color(red: 0.55, green: 0.52, blue: 0.46)
    static let tertiary = Color(red: 0.42, green: 0.40, blue: 0.35)
}

final class AppModel: ObservableObject {
    weak var owner: AppDelegate?
    @Published var screen: PopoverScreen = .home
    @Published var running = false
    @Published var desiredRunning: Bool?
    @Published var busy = false
    @Published var testing = false
    @Published var cancellingTest = false
    @Published var strategies: [Strategy] = []
    @Published var selectedStrategy = ""
    @Published var ipsetMode = "none"
    @Published var qualityLine: String?
    @Published var progressFraction: Double?
    @Published var progressDetail = "Подготовка"
    @Published var progressStrategy = ""
    @Published var versionLine = ""
    @Published var installedVersion = ""
    @Published var updateVersion = ""
    @Published var updateAvailable = false
    @Published var updating = false
    @Published var checkingUpdate = false
    @Published var hasError = false
    @Published var uptimeText = ""
    @Published var discordReach: Reachability = .unchecked
    @Published var youtubeReach: Reachability = .unchecked
    @Published var domainDraft = ""
    @Published var excludeDraft = ""
    @Published var domainNote = ""
    @Published var userDomains: [String] = []
    @Published var excludeDomains: [String] = []
    @Published var updateNotes = ""
    @Published var updateStatus = ""
    @Published var testRows: [StrategyTestRow] = []
    @Published var testBestNames: [String] = []
    @Published var testSummary = ""
    @Published var testTLS = ""

    var displayedRunning: Bool { desiredRunning ?? running }

    var selectedStrategyName: String {
        strategies.first { $0.id == selectedStrategy }?.name ?? selectedStrategy
    }
}

@main
struct NimbusMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let fileManager = FileManager.default
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var eventMonitor: Any?
    private var strategies: [Strategy] = []
    private var timer: Timer?
    private var updateTimer: Timer?
    private var timerInterval: TimeInterval = 0
    private var busy = false
    private var testing = false
    private var cancellingTest = false
    private var checkingForUpdate = false
    private var updating = false
    private var availableRelease: GitHubRelease?
    private var authorization: AuthorizationRef?
    private var dotView: StatusDotView?
    private var iconTimer: Timer?
    private var reachTimer: Timer?
    private var reachSession: URLSession?
    private var reachGeneration = 0
    private var starPhase: CGFloat = 0
    private var failed = false
    private var uptimeAnchorPID: pid_t = 0
    private var uptimeAnchor: Date?
    let model = AppModel()

    private let releaseURL = URL(string: "https://api.github.com/repos/samevamp/Nimbus/releases")!
    private let releaseAssetName = "Nimbus-macOS-universal.zip"
    private let progressPattern = try! NSRegularExpression(pattern: #"^Стратегия (\d+)/(\d+): (.+)$"#)

    private var dataRoot: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZapretMac", isDirectory: true)
    }

    private var payloadURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("Payload", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.owner = self
        NSApp.setActivationPolicy(.accessory)
        do {
            try initializeUserData()
            strategies = try loadStrategies()
            model.strategies = strategies
        } catch {
            showError(error.localizedDescription)
            NSApp.terminate(nil)
            return
        }
        buildStatusItem()
        refreshUI()
        showPendingUpdateError()
        scheduleTimer(2)
        checkForUpdate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        updateTimer?.invalidate()
        iconTimer?.invalidate()
        reachTimer?.invalidate()
        reachSession?.invalidateAndCancel()
        if let authorization {
            AuthorizationFree(authorization, [.destroyRights])
        }
    }

    func popoverDidShow(_ notification: Notification) {
        stylePopoverWindow()
        popover.contentViewController?.view.window?.makeKey()
        syncReachability(running: isRunning())
        if model.screen == .home || model.screen == .domains {
            reloadDomainLists()
        }
        applyStatusIcon(running: isRunning())
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        stopReachability()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        applyStatusIcon(running: isRunning())
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.setAccessibilityLabel("Zapret Mac")
            let dot = StatusDotView(frame: button.bounds)
            dot.autoresizingMask = [.width, .height]
            button.addSubview(dot)
            dotView = dot
        }
        let controller = PopoverHostingController(rootView: PopoverRoot(model: model))
        controller.sizingOptions = [.preferredContentSize]
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 640, height: 460)
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        refreshUI()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    private func stylePopoverWindow() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }

    private func scheduleTimer(_ interval: TimeInterval) {
        timer?.invalidate()
        timerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }
    }

    private func publish<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
        if model[keyPath: keyPath] != value {
            model[keyPath: keyPath] = value
        }
    }

    private func refreshUI() {
        guard statusItem != nil else { return }
        let running = isRunning()
        if !busy {
            publish(\.desiredRunning, nil)
        }
        publish(\.running, running)
        publish(\.busy, busy)
        publish(\.testing, testing)
        publish(\.cancellingTest, cancellingTest)
        publish(\.updating, updating)
        publish(\.updateAvailable, availableRelease != nil)
        publish(\.versionLine, versionTitle())
        let selectedStrategy = readState(from: dataRoot.appendingPathComponent("selected-strategy"))
        publish(\.selectedStrategy, selectedStrategy)
        let selectedIPSet = readState(from: dataRoot.appendingPathComponent("ipset-mode"))
        publish(\.ipsetMode, selectedIPSet.isEmpty ? "none" : selectedIPSet)
        publish(\.qualityLine, currentQualityLine(selectedStrategy: selectedStrategy))
        publish(\.installedVersion, currentVersion)
        publish(\.updateVersion, availableRelease.map { displayVersion($0.tagName) } ?? "")
        publish(\.hasError, failed)
        publish(\.uptimeText, uptimeLine(running: running))
        publishProgress()
        publishTestReport()
        syncReachability(running: running)
        syncStatusIcon(running: running)
        if popover.isShown {
            statusItem.button?.highlight(true)
        }
        let wanted: TimeInterval = testing ? 0.4 : 2
        if timerInterval != wanted {
            scheduleTimer(wanted)
        }
    }

    private func publishProgress() {
        let progress = readState(from: dataRoot.appendingPathComponent("strategy-test-progress"))
        var fraction: Double?
        var detail = progress
        var strategyName = ""
        let range = NSRange(progress.startIndex..., in: progress)
        if let match = progressPattern.firstMatch(in: progress, range: range),
           let currentRange = Range(match.range(at: 1), in: progress),
           let totalRange = Range(match.range(at: 2), in: progress),
           let nameRange = Range(match.range(at: 3), in: progress),
           let current = Double(progress[currentRange]),
           let total = Double(progress[totalRange]), total > 0 {
            fraction = min(1, current / total)
            detail = "\(progress[currentRange]) из \(progress[totalRange])"
            strategyName = String(progress[nameRange])
        } else if cancellingTest {
            detail = "Остановка теста…"
        } else if progress.isEmpty {
            detail = testing && model.testSummary.isEmpty ? "Подготовка" : ""
        }
        publish(\.progressFraction, fraction)
        publish(\.progressDetail, detail)
        publish(\.progressStrategy, strategyName)
    }

    private func publishTestReport() {
        let report = dataRoot.appendingPathComponent("strategy-test.txt")
        guard let text = try? String(contentsOf: report, encoding: .utf8) else { return }
        let parsed = parseStrategyReport(text)
        publish(\.testRows, parsed.rows)
        publish(\.testBestNames, parsed.bestNames)
        publish(\.testTLS, parsed.tls)
        if !testing,
           !parsed.summary.isEmpty,
           model.testSummary.hasPrefix(parsed.summary),
           model.testSummary.contains("Применена:") {
            return
        }
        publish(\.testSummary, parsed.summary)
    }


private func parseStrategyReport(_ text: String) -> (rows: [StrategyTestRow], bestNames: [String], summary: String, tls: String) {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    var rows: [StrategyTestRow] = []
    var bestNames: [String] = []
    var summary = ""
    var notes: [String] = []
    var tls = ""
    var inTable = false
    for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("TLS1.3:") {
            tls = trimmed
        }
        if trimmed == "Остановлено" {
            summary = trimmed
            continue
        }
        if trimmed.hasPrefix("Лучшая:") {
            summary = trimmed
            bestNames = bestStrategyNames(trimmed)
            inTable = false
            continue
        }
        if !inTable {
            if trimmed.hasPrefix("Strategy"), trimmed.contains("Score") {
                inTable = true
            }
            continue
        }
        if trimmed.isEmpty { continue }
        if trimmed == "Нет доступных IP" {
            if !notes.contains(trimmed) { notes.append(trimmed) }
            continue
        }
        if let row = parseStrategyLine(line) {
            rows.append(row)
        }
    }
    if !notes.isEmpty {
        let prefix = notes.joined(separator: "\n")
        if summary.isEmpty {
            summary = prefix
        } else if !summary.contains(prefix) {
            summary = prefix + "\n" + summary
        }
    }
    return (rows, bestNames, summary, tls)
}

private func parseStrategyLine(_ line: String) -> StrategyTestRow? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    if trimmed.contains("ошибка запуска") {
        let name = trimmed.replacingOccurrences(of: "ошибка запуска", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return StrategyTestRow(name: name, score: "ошибка запуска", detail: "")
    }
    let head: String
    let tail: String
    if line.count > 34 {
        let fixedName = String(line.prefix(34)).trimmingCharacters(in: .whitespaces)
        let fixedRest = String(line.dropFirst(34)).trimmingCharacters(in: .whitespaces)
        let first = fixedRest.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if first.contains("/") {
            head = fixedName
            tail = fixedRest
        } else if let split = splitStrategyScore(line) {
            head = split.0
            tail = split.1
        } else {
            return nil
        }
    } else if let split = splitStrategyScore(line) {
        head = split.0
        tail = split.1
    } else {
        return nil
    }
    guard !head.isEmpty else { return nil }
    let parts = tail.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let score = parts.first, score.contains("/") else {
        return StrategyTestRow(name: head, score: "", detail: tail)
    }
    let labels = ["Ping", "HTTP", "TLS1.2", "TLS1.3"]
    var bits: [String] = []
    for (offset, label) in labels.enumerated() {
        let index = offset + 1
        if index < parts.count {
            bits.append("\(label) \(parts[index])")
        }
    }
    return StrategyTestRow(name: head, score: score, detail: bits.joined(separator: " · "))
}

private func splitStrategyScore(_ line: String) -> (String, String)? {
    guard let range = line.range(of: #"\d+/\d+"#, options: .regularExpression) else { return nil }
    let name = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
    let rest = line[range.lowerBound...].trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return nil }
    return (name, String(rest))
}

private func bestStrategyNames(_ line: String) -> [String] {
    let prefix = "Лучшая:"
    guard line.hasPrefix(prefix) else { return [] }
    var body = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    if body == "не определена" || body.isEmpty { return [] }
    if body.hasSuffix(")"), let open = body.lastIndex(of: "(") {
        let inside = body[body.index(after: open)..<body.index(before: body.endIndex)]
        if inside.contains("/"), inside.allSatisfy({ $0.isNumber || $0 == "/" }) {
            body = body[..<open].trimmingCharacters(in: .whitespaces)
        }
    }
    return body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

    private func menuGlyph(running: Bool) -> MenuGlyph {
        if testing || busy { return .working }
        if failed { return .failed }
        if running { return .running }
        if availableRelease != nil { return .update }
        return .off
    }

    private func syncStatusIcon(running: Bool) {
        let animate = testing || (busy && model.desiredRunning != false)
        if animate {
            if iconTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.starPhase += 0.28
                    self.applyStatusIcon(running: self.model.running)
                }
                RunLoop.main.add(timer, forMode: .common)
                iconTimer = timer
            }
        } else {
            iconTimer?.invalidate()
            iconTimer = nil
            starPhase = 0
        }
        applyStatusIcon(running: running)
    }

    private func applyStatusIcon(running: Bool) {
        guard let button = statusItem?.button else { return }
        let glyph = menuGlyph(running: running)
        let animate = testing || (busy && model.desiredRunning != false)
        button.image = menuGlyphImage(dimmed: glyph == .off, animated: animate, phase: starPhase)
        dotView?.dotColor = menuDotColor(glyph)
        switch glyph {
        case .off:
            button.toolTip = "Nimbus выключен"
        case .running:
            button.toolTip = "Nimbus запущен"
        case .working:
            button.toolTip = testing ? "Подбор стратегии" : "Nimbus запускается"
        case .update:
            button.toolTip = "Доступно обновление"
        case .failed:
            button.toolTip = "Ошибка Nimbus"
        }
    }

    private func menuDotColor(_ glyph: MenuGlyph) -> NSColor? {
        switch glyph {
        case .off: return nil
        case .running: return .systemGreen
        case .working: return .systemOrange
        case .update: return .systemBlue
        case .failed: return .systemRed
        }
    }

    private func menuGlyphImage(dimmed: Bool, animated: Bool, phase: CGFloat) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.withAlphaComponent(dimmed ? 0.38 : 1).setFill()
            moonContour(in: NSRect(x: rect.minX + 0.15, y: rect.minY + 2.05, width: 11.5, height: 14.5)).fill()
            let twinkle: CGFloat = animated ? (0.8 + 0.2 * abs(sin(phase))) : 1
            fourPointStar(
                center: CGPoint(x: rect.maxX - 3.65, y: rect.maxY - 4.55),
                outer: 3.0 * twinkle,
                inner: 1.1,
                rotation: animated ? phase : 0
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func uptimeLine(running: Bool) -> String {
        guard running else {
            uptimeAnchorPID = 0
            uptimeAnchor = nil
            return ""
        }
        let pid = utunPID()
        guard pid > 0 else { return "" }
        if pid != uptimeAnchorPID || uptimeAnchor == nil {
            uptimeAnchorPID = pid
            if let seconds = etimeSeconds(pid: pid) {
                uptimeAnchor = Date().addingTimeInterval(-seconds)
            }
        }
        guard let uptimeAnchor else { return "" }
        return "работает " + formatUptime(Date().timeIntervalSince(uptimeAnchor))
    }

    private func utunPID() -> pid_t {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "utunws"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return 0 }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return pid_t(first.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } catch {
            return 0
        }
    }

    private func etimeSeconds(pid: pid_t) -> TimeInterval? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "etime="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return parseEtime(raw)
        } catch {
            return nil
        }
    }

    private func parseEtime(_ raw: String) -> TimeInterval? {
        var days = 0
        var clock = raw
        if let dash = raw.firstIndex(of: "-") {
            days = Int(raw[..<dash]) ?? 0
            clock = String(raw[raw.index(after: dash)...])
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let seconds: Int
        switch parts.count {
        case 3: seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: seconds = parts[0] * 60 + parts[1]
        case 1: seconds = parts[0]
        default: return nil
        }
        return TimeInterval(days * 86400 + seconds)
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) д \(hours) ч" }
        if hours > 0 { return "\(hours) ч \(minutes) мин" }
        if minutes > 0 { return "\(minutes) мин" }
        return "меньше минуты"
    }

    private func syncReachability(running: Bool) {
        let shouldProbe = popover.isShown && running
        if shouldProbe {
            if reachTimer == nil {
                startReachability()
            }
            return
        }
        if reachTimer != nil || reachSession != nil {
            stopReachability()
        }
        if !running {
            publish(\.discordReach, .unchecked)
            publish(\.youtubeReach, .unchecked)
        }
    }

    private func startReachability() {
        guard isRunning() else {
            publish(\.discordReach, .unchecked)
            publish(\.youtubeReach, .unchecked)
            return
        }
        reachTimer?.invalidate()
        reachSession?.invalidateAndCancel()
        reachSession = nil
        reachGeneration += 1
        publish(\.discordReach, .checking)
        publish(\.youtubeReach, .checking)
        probeReachability()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.probeReachability()
        }
        RunLoop.main.add(timer, forMode: .common)
        reachTimer = timer
    }

    private func stopReachability() {
        reachTimer?.invalidate()
        reachTimer = nil
        reachGeneration += 1
        reachSession?.invalidateAndCancel()
        reachSession = nil
    }

    private func reachabilitySession() -> URLSession {
        if let reachSession { return reachSession }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        config.urlCache = nil
        let session = URLSession(configuration: config)
        reachSession = session
        return session
    }

    private func probeReachability() {
        guard popover.isShown, isRunning() else { return }
        probeHost("discord.com", keyPath: \.discordReach)
        probeHost("youtube.com", keyPath: \.youtubeReach)
    }

    private func probeHost(_ host: String, keyPath: ReferenceWritableKeyPath<AppModel, Reachability>) {
        let generation = reachGeneration
        guard let url = URL(string: "https://\(host)/") else { return }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        reachabilitySession().dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self, generation == self.reachGeneration, self.popover.isShown, self.isRunning() else { return }
                if (error as NSError?)?.code == NSURLErrorCancelled { return }
                let ok = (response as? HTTPURLResponse).map { (200..<500).contains($0.statusCode) } ?? false
                self.publish(keyPath, ok ? .up : .down)
            }
        }.resume()
    }

    func openDomains() {
        reloadDomainLists()
        publish(\.domainNote, "")
        model.screen = .domains
    }

    func reloadDomainLists() {
        publish(\.userDomains, readDomainLines("list-general-user.txt"))
        publish(\.excludeDomains, readDomainLines("list-exclude-user.txt"))
    }

    func addUserDomain() {
        addListedDomain(file: "list-general-user.txt", domainsKey: \.userDomains, draftKey: \.domainDraft)
    }

    func addExcludeDomain() {
        addListedDomain(file: "list-exclude-user.txt", domainsKey: \.excludeDomains, draftKey: \.excludeDraft)
    }

    func removeUserDomain(_ domain: String) {
        let domains = model.userDomains.filter { $0.caseInsensitiveCompare(domain) != .orderedSame }
        commitDomainList("list-general-user.txt", domains: domains, keyPath: \.userDomains, clearDraft: nil)
    }

    func removeExcludeDomain(_ domain: String) {
        let domains = model.excludeDomains.filter { $0.caseInsensitiveCompare(domain) != .orderedSame }
        commitDomainList("list-exclude-user.txt", domains: domains, keyPath: \.excludeDomains, clearDraft: nil)
    }

    private func addListedDomain(
        file: String,
        domainsKey: ReferenceWritableKeyPath<AppModel, [String]>,
        draftKey: ReferenceWritableKeyPath<AppModel, String>
    ) {
        let raw = model[keyPath: draftKey].trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains(where: \.isWhitespace) {
            publish(\.domainNote, "В имени не должно быть пробелов")
            return
        }
        guard let domain = normalizedDomain(raw) else {
            publish(\.domainNote, "Некорректное имя домена")
            return
        }
        var domains = model[keyPath: domainsKey]
        if domains.contains(where: { $0.caseInsensitiveCompare(domain) == .orderedSame }) {
            publish(\.domainNote, "Уже в списке")
            return
        }
        domains.append(domain)
        commitDomainList(file, domains: domains, keyPath: domainsKey, clearDraft: draftKey)
    }

    private func commitDomainList(
        _ name: String,
        domains: [String],
        keyPath: ReferenceWritableKeyPath<AppModel, [String]>,
        clearDraft: ReferenceWritableKeyPath<AppModel, String>?
    ) {
        do {
            try writeDomainLines(name, domains: domains)
            publish(keyPath, domains)
            if let clearDraft {
                model[keyPath: clearDraft] = ""
            }
            if isRunning() && !busy {
                publish(\.domainNote, "Сохранено, защита перезапускается")
                applyIfRunning()
            } else if isRunning() {
                publish(\.domainNote, "Сохранено. Применится после перезапуска")
            } else {
                publish(\.domainNote, "Сохранено")
            }
        } catch {
            publish(\.domainNote, error.localizedDescription)
        }
    }

    private func domainListURL(_ name: String) -> URL {
        dataRoot.appendingPathComponent("lists", isDirectory: true).appendingPathComponent(name)
    }

    private func readDomainLines(_ name: String) -> [String] {
        guard let text = try? String(contentsOf: domainListURL(name), encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var lines: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value.hasPrefix("#") { continue }
            if seen.insert(value.lowercased()).inserted {
                lines.append(value)
            }
        }
        return lines
    }

    private func writeDomainLines(_ name: String, domains: [String]) throws {
        let file = domainListURL(name)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fileManager.destinationOfSymbolicLink(atPath: file.path)) != nil {
            throw NSError(domain: "Nimbus.Lists", code: 1, userInfo: [NSLocalizedDescriptionKey: "Файл списка является ссылкой и не изменён"])
        }
        let text = domains.isEmpty ? "" : domains.joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func normalizedDomain(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("https://") { value.removeFirst("https://".count) }
        else if value.hasPrefix("http://") { value.removeFirst("http://".count) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        while value.hasSuffix(".") { value.removeLast() }
        guard value.count <= 253 else { return nil }
        let pattern = #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return value
    }


    private func initializeUserData() throws {
        let lists = dataRoot.appendingPathComponent("lists", isDirectory: true)
        try fileManager.createDirectory(at: lists, withIntermediateDirectories: true)
        let defaults = payloadURL.appendingPathComponent("default-lists", isDirectory: true)
        for name in try fileManager.contentsOfDirectory(atPath: defaults.path) {
            let target = lists.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: defaults.appendingPathComponent(name), to: target)
            }
        }
        let strategyFile = dataRoot.appendingPathComponent("selected-strategy")
        if !fileManager.fileExists(atPath: strategyFile.path) {
            try writeState("general-simple-fake", to: strategyFile)
        }
        let ipsetFile = dataRoot.appendingPathComponent("ipset-mode")
        if !fileManager.fileExists(atPath: ipsetFile.path) {
            try writeState("none", to: ipsetFile)
        }
    }

    private func loadStrategies() throws -> [Strategy] {
        let text = try String(contentsOf: payloadURL.appendingPathComponent("strategies.tsv"), encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return fields.count == 2 ? Strategy(id: fields[0], name: fields[1]) : nil
        }
    }

    private func isRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "utunws"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func readState(from url: URL) -> String {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeState(_ value: String, to url: URL) throws {
        try (value + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func currentQualityLine(selectedStrategy: String) -> String? {
        let direct = dataRoot.appendingPathComponent("connection-quality")
        if let raw = try? String(contentsOf: direct, encoding: .utf8) {
            let line = raw.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !line.isEmpty { return line }
        }
        guard let name = strategies.first(where: { $0.id == selectedStrategy })?.name, !name.isEmpty else { return nil }
        let report = dataRoot.appendingPathComponent("strategy-test.txt")
        guard let text = try? String(contentsOf: report, encoding: .utf8) else { return nil }
        for lineSub in text.split(whereSeparator: \.isNewline) {
            let line = String(lineSub)
            guard line.count >= 34 else { continue }
            let prefix = line.prefix(34).trimmingCharacters(in: .whitespaces)
            guard prefix == name else { continue }
            let rest = line.dropFirst(34).trimmingCharacters(in: .whitespaces)
            if let score = rest.split(separator: " ").first, score.contains("/") {
                return "Качество: \(score)"
            }
        }
        return nil
    }

    @objc func toggleService() {
        if busy { return }
        let enable = !isRunning()
        model.desiredRunning = enable
        if enable {
            runPrivileged(script: "install.sh", arguments: [dataRoot.path])
        } else {
            runPrivileged(script: "stop.sh", arguments: [])
        }
    }

    func selectStrategy(_ id: String) {
        guard !busy, id != model.selectedStrategy else { return }
        do {
            try writeState(id, to: dataRoot.appendingPathComponent("selected-strategy"))
            publish(\.selectedStrategy, id)
            applyIfRunning()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func selectIPSet(_ mode: String) {
        guard !busy, mode != model.ipsetMode, ["none", "loaded", "any"].contains(mode) else { return }
        do {
            try writeState(mode, to: dataRoot.appendingPathComponent("ipset-mode"))
            publish(\.ipsetMode, mode)
            applyIfRunning()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func applyIfRunning() {
        if isRunning() {
            runPrivileged(script: "restart.sh", arguments: [])
        }
    }

    func openLists() {
        let lists = dataRoot.appendingPathComponent("lists", isDirectory: true)
        try? fileManager.createDirectory(at: lists, withIntermediateDirectories: true)
        NSWorkspace.shared.open(lists)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func versionTitle() -> String {
        if updating {
            return "Установка обновления…"
        }
        return "Версия \(currentVersion)"
    }

    private func displayVersion(_ version: String) -> String {
        version.first == "v" || version.first == "V" ? String(version.dropFirst()) : version
    }

    private func bundledVersion(_ releaseVersion: String) -> String {
        displayVersion(releaseVersion).split(separator: "-", maxSplits: 1).first.map(String.init) ?? displayVersion(releaseVersion)
    }

    private func shortChangelog(_ body: String?) -> String {
        guard let body else { return "" }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var kept: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !kept.isEmpty { break }
                continue
            }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("**full changelog") || lower.hasPrefix("full changelog") { break }
            var line = trimmed
            if line.hasPrefix("- ") { line.removeFirst(2) }
            else if line.hasPrefix("* ") { line.removeFirst(2) }
            line = line.replacingOccurrences(of: "**", with: "")
            if line.hasPrefix("#") {
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty { continue }
            if line.count > 180 {
                line = String(line.prefix(179)) + "…"
            }
            kept.append(line)
            if kept.count == 3 { break }
        }
        return kept.joined(separator: "\n")
    }

    func checkForUpdatesNow() {
        checkForUpdate(interactive: true)
    }

    private func checkForUpdate(interactive: Bool = false) {
        if checkingForUpdate || updating { return }
        checkingForUpdate = true
        publish(\.checkingUpdate, true)
        if interactive {
            publish(\.updateStatus, "")
        }
        let url = URL(string: releaseURL.absoluteString + "?t=\(Int(Date().timeIntervalSince1970 * 1000))&per_page=1")!
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Nimbus", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            var release: GitHubRelease?
            var completed = false
            if let response = response as? HTTPURLResponse,
               response.statusCode == 200,
               let data,
               let decoded = try? JSONDecoder().decode([GitHubRelease].self, from: data),
               let latest = decoded.first {
                completed = true
                if latest.assets.contains(where: { $0.name == self.releaseAssetName }),
                   self.isNewer(latest.tagName, than: self.currentVersion) {
                    release = latest
                }
            }
            let notes = self.shortChangelog(release?.body)
            let interactive = interactive
            DispatchQueue.main.async {
                self.checkingForUpdate = false
                self.publish(\.checkingUpdate, false)
                if completed {
                    self.availableRelease = release
                    self.publish(\.updateNotes, notes)
                    if release == nil {
                        if interactive {
                            self.publish(\.updateStatus, "Обновлений нет")
                        }
                    } else {
                        self.publish(\.updateStatus, "")
                    }
                } else if interactive {
                    self.publish(\.updateStatus, "Не удалось проверить обновления")
                }
                self.refreshUI()
            }
        }.resume()
    }

    private func isNewer(_ candidate: String, than installed: String) -> Bool {
        bundledVersion(candidate).compare(displayVersion(installed), options: [.numeric, .caseInsensitive]) == .orderedDescending
    }

    func installUpdate() {
        guard let release = availableRelease,
              let asset = release.assets.first(where: { $0.name == releaseAssetName }),
              !updating else { return }
        let target = Bundle.main.bundleURL.standardizedFileURL
        guard target.pathExtension == "app",
              !target.path.contains("/AppTranslocation/") else {
            showError("Переместите Nimbus.app из защищённой папки (например, в папку Applications) и запустите снова")
            return
        }
        updating = true
        refreshUI()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let source = self.fileManager.temporaryDirectory.appendingPathComponent("Nimbus-\(UUID().uuidString).zip")
            do {
                let arguments = ["-fL", "--connect-timeout", "5", "-A", "Nimbus", "-o", source.path, asset.downloadURL.absoluteString]
                do {
                    try self.runProcess("/usr/bin/curl", arguments: ["--resolve", "release-assets.githubusercontent.com:443:185.199.109.133", "--max-time", "30"] + arguments)
                } catch {
                    try? self.fileManager.removeItem(at: source)
                    try self.runProcess("/usr/bin/curl", arguments: ["--max-time", "120"] + arguments)
                }
                try self.prepareAndLaunchUpdate(source: source, release: release, asset: asset, target: target)
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            } catch {
                try? self.fileManager.removeItem(at: source)
                DispatchQueue.main.async {
                    self.updating = false
                    self.refreshUI()
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func prepareAndLaunchUpdate(source: URL, release: GitHubRelease, asset: GitHubReleaseAsset, target: URL) throws {
        let workRoot = fileManager.temporaryDirectory.appendingPathComponent("Nimbus-Update-\(UUID().uuidString)", isDirectory: true)
        let archive = workRoot.appendingPathComponent(releaseAssetName)
        let extracted = workRoot.appendingPathComponent("extracted", isDirectory: true)
        do {
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: archive)
            try verifyDigest(of: archive, expected: asset.digest)
            try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, extracted.path])
            let app = extracted.appendingPathComponent("Nimbus.app", isDirectory: true)
            try verifyUpdate(app, version: release.tagName)
            let updater = payloadURL.appendingPathComponent("update-app.sh")
            let updaterCopy = workRoot.appendingPathComponent("update-app.sh")
            try fileManager.copyItem(at: updater, to: updaterCopy)
            let log = dataRoot.appendingPathComponent("update.log")
            let backup = target.deletingLastPathComponent().appendingPathComponent("Nimbus.app.backup")
            let launch = ([
                "/usr/bin/nohup", "/bin/sh", updaterCopy.path, app.path, target.path,
                String(ProcessInfo.processInfo.processIdentifier), workRoot.path,
                isRunning() ? "1" : "0", dataRoot.path, String(getuid()), String(getgid())
            ].map(shellQuote).joined(separator: " ")) + " >\(shellQuote(log.path)) 2>&1 </dev/null &"
            let command = "/bin/rm -rf \(shellQuote(backup.path)) && /usr/bin/ditto \(shellQuote(target.path)) \(shellQuote(backup.path)) && " + launch
            let result = try executePrivileged(command: command)
            guard result.status == 0 else {
                throw NSError(domain: "Nimbus.Update", code: 2, userInfo: [NSLocalizedDescriptionKey: result.output.isEmpty ? "Не удалось запустить установку обновления" : result.output])
            }
        } catch {
            try? fileManager.removeItem(at: workRoot)
            throw error
        }
    }

    private func verifyDigest(of archive: URL, expected: String?) throws {
        guard let expected, expected.hasPrefix("sha256:") else { return }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(String(expected.dropFirst(7))) == .orderedSame else {
            throw NSError(domain: "Nimbus.Update", code: 3, userInfo: [NSLocalizedDescriptionKey: "Контрольная сумма обновления не совпала"])
        }
    }

    private func verifyUpdate(_ app: URL, version: String) throws {
        guard fileManager.fileExists(atPath: app.path),
              let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let bundledVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              displayVersion(bundledVersion) == self.bundledVersion(version) else {
            throw NSError(domain: "Nimbus.Update", code: 4, userInfo: [NSLocalizedDescriptionKey: "Архив релиза содержит неподходящую версию приложения"])
        }
        try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app.path])
        let executable = app.appendingPathComponent("Contents/MacOS/Nimbus")
        try runProcess("/usr/bin/lipo", arguments: [executable.path, "-verify_arch", "x86_64", "arm64"])
    }

    private func runProcess(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "Nimbus.Update", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Проверка обновления не пройдена"])
        }
    }

    private func showPendingUpdateError() {
        let file = dataRoot.appendingPathComponent("update-error")
        guard let message = try? String(contentsOf: file, encoding: .utf8), !message.isEmpty else { return }
        try? fileManager.removeItem(at: file)
        showError(message)
    }

    func beginTest() {
        if testing { return }
        if busy { return }
        let report = dataRoot.appendingPathComponent("strategy-test.txt")
        let cancel = dataRoot.appendingPathComponent("strategy-test-cancel")
        try? "".write(to: report, atomically: true, encoding: .utf8)
        try? fileManager.removeItem(at: cancel)
        publish(\.testRows, [])
        publish(\.testBestNames, [])
        publish(\.testSummary, "")
        publish(\.testTLS, "")
        testing = true
        cancellingTest = false
        refreshUI()
        runPrivileged(
            script: "test-strategies.sh",
            arguments: [dataRoot.path, String(getuid()), String(getgid())]
        ) { [weak self] failure in
            guard let self else { return }
            self.testing = false
            self.cancellingTest = false
            try? self.fileManager.removeItem(at: cancel)
            self.publishTestReport()
            if failure == nil,
               self.model.testSummary.isEmpty,
               !self.fileManager.fileExists(atPath: report.path) {
                self.publish(\.testSummary, "Отчёт тестирования не найден")
            }
            self.refreshUI()
        }
    }

    func applyTestedStrategy() {
        guard !busy, !testing else { return }
        guard let name = model.testBestNames.first else { return }
        guard let strategy = strategies.first(where: { $0.name == name }) else {
            showError("Стратегия «\(name)» не найдена среди установленных")
            return
        }
        do {
            try writeState(strategy.id, to: dataRoot.appendingPathComponent("selected-strategy"))
            publish(\.selectedStrategy, strategy.id)
            let applied = "Применена: \(name)"
            if model.testSummary.contains(applied) == false {
                if model.testSummary.isEmpty {
                    publish(\.testSummary, applied)
                } else {
                    publish(\.testSummary, model.testSummary + "\n" + applied)
                }
            }
            applyIfRunning()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func stopTest() {
        let cancel = dataRoot.appendingPathComponent("strategy-test-cancel")
        guard testing, !cancellingTest else { return }
        do {
            try Data().write(to: cancel, options: .atomic)
            cancellingTest = true
            refreshUI()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func runPrivileged(script: String, arguments: [String], completion: ((String?) -> Void)? = nil) {
        if busy { return }
        busy = true
        refreshUI()
        let payload = payloadURL
        let dataArguments = arguments
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var failure: String?
            let stagingRoot = self.fileManager.temporaryDirectory.appendingPathComponent("Nimbus-\(UUID().uuidString)", isDirectory: true)
            let stagedPayload = stagingRoot.appendingPathComponent("Payload", isDirectory: true)
            do {
                try self.fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
                try self.fileManager.copyItem(at: payload, to: stagedPayload)
                var commandArguments = [stagedPayload.path]
                if script == "install.sh" || script == "test-strategies.sh" {
                    commandArguments = [stagedPayload.path] + dataArguments
                } else {
                    commandArguments = dataArguments
                }
                let command = (["/bin/sh", stagedPayload.appendingPathComponent(script).path] + commandArguments)
                    .map(self.shellQuote)
                    .joined(separator: " ")
                let result = try self.executePrivileged(command: command + " 2>&1")
                if result.status != 0 {
                    failure = result.output.isEmpty ? "Операция не выполнена" : result.output
                    let diagnostics = self.serviceDiagnostics()
                    if !diagnostics.isEmpty {
                        failure = (failure ?? "Операция не выполнена") + "\n\n" + diagnostics
                    }
                }
            } catch {
                failure = error.localizedDescription
            }
            try? self.fileManager.removeItem(at: stagingRoot)
            DispatchQueue.main.async {
                self.busy = false
                if failure == nil {
                    self.failed = false
                } else {
                    self.failed = true
                }
                self.refreshUI()
                if let failure { self.showError(failure) }
                completion?(failure)
            }
        }
    }

    private func executePrivileged(command: String) throws -> (status: Int32, output: String) {
        var auth = authorization
        if auth == nil {
            let status = kAuthorizationRightExecute.withCString { name in
                var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                return withUnsafeMutablePointer(to: &item) { item in
                    var rights = AuthorizationRights(count: 1, items: item)
                    return AuthorizationCreate(&rights, nil, [.interactionAllowed, .extendRights], &auth)
                }
            }
            guard status == errAuthorizationSuccess, let auth else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
            authorization = auth
        }
        guard let auth else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAuthorizationInvalidRef)) }
        let arguments = calloc(3, MemoryLayout<UnsafeMutablePointer<CChar>>.stride)!
            .bindMemory(to: UnsafeMutablePointer<CChar>.self, capacity: 3)
        arguments[0] = strdup("-c")!
        let marker = "ZAPRET_EXIT_STATUS="
        let wrappedCommand = command + "\nresult=$?\nprintf '\\n" + marker + "%d\\n' \"$result\""
        arguments[1] = strdup(wrappedCommand)!
        defer {
            free(arguments[0])
            free(arguments[1])
            free(arguments)
        }
        var pipe: UnsafeMutablePointer<FILE>?
        let executeStatus = "/bin/sh".withCString {
            executeWithPrivileges(auth, $0, [], arguments, &pipe)
        }
        guard executeStatus == errAuthorizationSuccess, let pipe else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(executeStatus))
        }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = fread(&buffer, 1, buffer.count, pipe)
            if count == 0 { break }
            output.append(buffer, count: count)
        }
        fclose(pipe)
        var text = String(data: output, encoding: .utf8) ?? ""
        guard let range = text.range(of: marker, options: .backwards) else { return (1, text) }
        let statusText = text[range.upperBound...].prefix { $0.isNumber }
        let exitStatus = Int32(statusText) ?? 1
        text.removeSubrange(range.lowerBound...)
        return (exitStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func serviceDiagnostics() -> String {
        let root = URL(fileURLWithPath: "/Library/Application Support/ZapretMac", isDirectory: true)
        for name in ["engine.log", "zapret.log"] {
            let url = root.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let lines = text.split(whereSeparator: \.isNewline).suffix(18)
                if !lines.isEmpty { return lines.joined(separator: "\n") }
            }
        }
        return ""
    }

    private func showError(_ message: String, icon: Bool = true) {
        let present = {
            if icon {
                self.failed = true
                self.publish(\.hasError, true)
                self.applyStatusIcon(running: self.model.running)
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Nimbus"
            alert.informativeText = message
            alert.runModal()
        }
        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.async(execute: present)
        }
    }

    private func showInformation(_ message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nimbus"
            alert.informativeText = message
            alert.runModal()
        }
    }
}

private func moonContour(in rect: NSRect) -> NSBezierPath {
    let radius = min(rect.width, rect.height) / 2
    guard radius > 1 else { return NSBezierPath(ovalIn: rect) }
    let outer = CGPoint(x: rect.midX - radius * 0.06, y: rect.midY)
    let inner = CGPoint(x: rect.midX + radius * 0.46, y: rect.midY)
    let innerRadius = radius * 0.88
    let dx = inner.x - outer.x
    let dy = inner.y - outer.y
    let distance = max(hypot(dx, dy), 0.001)
    let along = (radius * radius - innerRadius * innerRadius + distance * distance) / (2 * distance)
    let heightSquared = radius * radius - along * along
    guard heightSquared > 0 else { return NSBezierPath(ovalIn: rect) }
    let height = sqrt(heightSquared)
    let pivotX = outer.x + along * dx / distance
    let pivotY = outer.y + along * dy / distance
    let top = CGPoint(x: pivotX + height * dy / distance, y: pivotY - height * dx / distance)
    let bottom = CGPoint(x: pivotX - height * dy / distance, y: pivotY + height * dx / distance)
    func degrees(_ center: CGPoint, _ point: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }
    let path = NSBezierPath()
    path.move(to: top)
    path.appendArc(withCenter: outer, radius: radius, startAngle: degrees(outer, top), endAngle: degrees(outer, bottom), clockwise: true)
    path.appendArc(withCenter: inner, radius: innerRadius, startAngle: degrees(inner, bottom), endAngle: degrees(inner, top), clockwise: false)
    path.close()
    return path
}

private func fourPointStar(center: CGPoint, outer: CGFloat, inner: CGFloat, rotation: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for index in 0..<8 {
        let angle = rotation + (CGFloat(index) * .pi / 4) - (.pi / 2)
        let radius = index.isMultiple(of: 2) ? outer : inner
        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if index == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }
    path.close()
    return path
}

final class StatusDotView: NSView {
    var dotColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let dotColor else { return }
        let side: CGFloat = 18
        let imageRect = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        let dot = NSRect(x: imageRect.maxX - 6.1, y: imageRect.minY - 0.15, width: 5.3, height: 5.3)
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: -0.7, dy: -0.7)).fill()
        dotColor.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}


private func cgPath(_ path: NSBezierPath) -> CGPath {
    let result = CGMutablePath()
    var points = [NSPoint](repeating: .zero, count: 3)
    for index in 0..<path.elementCount {
        let kind = path.element(at: index, associatedPoints: &points)
        switch kind {
        case .moveTo:
            result.move(to: points[0])
        case .lineTo:
            result.addLine(to: points[0])
        case .curveTo, .cubicCurveTo:
            result.addCurve(to: points[2], control1: points[0], control2: points[1])
        case .quadraticCurveTo:
            result.addQuadCurve(to: points[1], control: points[0])
        case .closePath:
            result.closeSubpath()
        @unknown default:
            break
        }
    }
    return result
}


struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = ZapretTheme.popoverRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = NSAppearance(named: .darkAqua)
        nsView.layer?.cornerRadius = ZapretTheme.popoverRadius
        nsView.layer?.cornerCurve = .continuous
    }
}

final class PopoverHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = ZapretTheme.popoverRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.appearance = NSAppearance(named: .darkAqua)
        view.window?.isOpaque = false
        view.window?.backgroundColor = .clear
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: ZapretTheme.cardRadius, style: .continuous)
                    .fill(ZapretTheme.softFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: ZapretTheme.cardRadius, style: .continuous)
                            .stroke(ZapretTheme.hairline, lineWidth: 1)
                    }
            }
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Color.white : ZapretTheme.text)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fillColor(pressed: configuration.isPressed))
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func fillColor(pressed: Bool) -> Color {
        if prominent {
            return ZapretTheme.accent.opacity(pressed ? 0.82 : 1)
        }
        return Color.white.opacity(pressed ? 0.10 : 0.06)
    }
}


enum ReachBrand {
    case discord
    case youtube
}

private struct DiscordRowMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 88.0 / 255.0, green: 101.0 / 255.0, blue: 242.0 / 255.0))
            VStack(spacing: 2.5) {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 3.2, height: 3.2)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 3.2, height: 3.2)
                }
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 9, height: 2.2)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct YouTubeRowMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 1, green: 0, blue: 51.0 / 255.0))
            PlayGlyph()
                .fill(Color.white)
                .frame(width: 8, height: 9)
                .offset(x: 0.6)
        }
        .frame(width: 22, height: 22)
    }
}

private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ReachPill: View {
    let title: String
    let host: String
    let mark: ReachBrand
    let state: Reachability

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch mark {
                case .discord:
                    DiscordRowMark()
                case .youtube:
                    YouTubeRowMark()
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ZapretTheme.text)
                    .lineLimit(1)
                Text(host)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ZapretTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(valueText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueText: String {
        switch state {
        case .unchecked: return "не проверено"
        case .checking: return "проверяем"
        case .up: return "открывается"
        case .down: return "не открывается"
        }
    }

    private var dotColor: Color {
        switch state {
        case .unchecked: return Color.white.opacity(0.28)
        case .checking: return Color.white.opacity(0.32)
        case .up: return ZapretTheme.running
        case .down: return Color(red: 0.92, green: 0.40, blue: 0.36)
        }
    }

    private var valueColor: Color {
        switch state {
        case .unchecked: return ZapretTheme.secondary
        case .checking: return ZapretTheme.secondary
        case .up: return ZapretTheme.running
        case .down: return Color(red: 0.92, green: 0.40, blue: 0.36)
        }
    }
}

struct SettingRow: View {
    let title: String
    var value: String?
    var chevron = "chevron.right"

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ZapretTheme.text)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ZapretTheme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Image(systemName: chevron)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ZapretTheme.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct HeroMoonMark: View {
    var lit: Bool
    var side: CGFloat = 22

    var body: some View {
        ZStack {
            if lit {
                Circle()
                    .fill(ZapretTheme.accent.opacity(0.28))
                    .blur(radius: 5)
                    .frame(width: side + 6, height: side + 6)
            }
            Canvas { context, size in
                let moon = moonContour(in: NSRect(x: size.width * 0.08, y: size.height * 0.08, width: size.width * 0.58, height: size.height * 0.84))
                let star = fourPointStar(
                    center: CGPoint(x: size.width * 0.74, y: size.height * 0.68),
                    outer: size.width * 0.15,
                    inner: size.width * 0.055,
                    rotation: 0
                )
                context.fill(Path(cgPath(moon)), with: .foreground)
                context.fill(Path(cgPath(star)), with: .foreground)
            }
            .frame(width: side, height: side)
            .foregroundStyle(lit ? ZapretTheme.accent : Color.white.opacity(0.78))
        }
        .frame(width: side + 4, height: side + 4)
        .accessibilityHidden(true)
    }
}

struct PopoverRoot: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.screen != .home {
                screenHeader
            }
            pane
        }
        .frame(
            width: model.screen == .home ? ZapretTheme.popoverWidth : ZapretTheme.narrowWidth,
            height: model.screen == .home ? ZapretTheme.popoverHeight : 520
        )
        .tint(ZapretTheme.accent)
        .environment(\.colorScheme, .dark)
        .background {
            ZStack {
                PopoverMaterial()
                ZapretTheme.background.opacity(0.99)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ZapretTheme.popoverRadius, style: .continuous))
        .onChange(of: model.screen) { _, screen in
            if screen == .domains {
                model.owner?.reloadDomainLists()
            }
        }
    }

    private var screenHeader: some View {
        HStack(spacing: 10) {
            Button {
                model.screen = .home
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZapretTheme.text)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Назад")
            Text(screenTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ZapretTheme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 2)
    }

    private var screenTitle: String {
        switch model.screen {
        case .home: return "Zapret"
        case .domains: return "Списки сайтов"
        case .test: return "Стратегия"
        case .more: return "Ещё"
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch model.screen {
        case .home:
            HomeScreen(model: model)
        case .domains:
            DomainsScreen(model: model)
        case .test:
            TestScreen(model: model)
        case .more:
            HomeScreen(model: model)
        }
    }
}

private struct ChipHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        for row in rows {
            for item in row.items {
                let subview = subviews[item.index]
                subview.place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(width: item.width, height: item.height)
                )
            }
        }
    }

    private struct Item {
        var index: Int
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [Item]
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var items: [Item] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        func closeRow() {
            guard !items.isEmpty else { return }
            rows.append(Row(y: y, height: rowHeight, items: items))
            y += rowHeight + lineSpacing
            x = 0
            rowHeight = 0
            items = []
        }

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth + 0.5 {
                closeRow()
            }
            items.append(Item(index: index, x: x, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        closeRow()
        return rows
    }
}

private struct ProgressRing: View {
    var fraction: Double?
    var side: CGFloat = 54

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: line)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(ZapretTheme.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if side >= 48 {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ZapretTheme.text)
                        .monospacedDigit()
                }
            } else {
                TimelineView(.animation) { context in
                    let turns = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.05) / 1.05
                    Circle()
                        .trim(from: 0.08, to: 0.72)
                        .stroke(ZapretTheme.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(turns * 360 - 90))
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var line: CGFloat { side >= 48 ? 4 : 2.5 }
}

private enum StrategyCopy {
    static func headline(for strategy: Strategy) -> String {
        headlines[strategy.id.lowercased()] ?? strategy.name
    }

    static func detail(for strategy: Strategy) -> String {
        details[strategy.id.lowercased()] ?? ""
    }

    private static let headlines: [String: String] = [
        "general": "Режет начало соединения с YouTube",
        "general-alt": "Подменяет TLS у YouTube и режет начало",
        "general-alt2": "Режет начало соединения с YouTube",
        "general-alt3": "Подменяет TLS и имя сайта у YouTube",
        "general-alt4": "Подменяет TLS у YouTube и сдвигает номер",
        "general-alt5": "Короткий обход для YouTube",
        "general-alt6": "Режет начало соединения с YouTube",
        "general-alt7": "Режет начало соединения с YouTube",
        "general-alt8": "Подменяет TLS у YouTube и сдвигает номер",
        "general-alt9": "Подменяет имя сайта у YouTube",
        "general-alt10": "Подменяет TLS у YouTube",
        "general-alt11": "Подменяет TLS у YouTube и режет начало",
        "general-alt12": "Подменяет имя сайта у YouTube и режет начало",
        "general-exp": "Экспериментальный обход QUIC для YouTube",
        "general-fake-tls-auto": "Подменяет TLS у YouTube",
        "general-fake-tls-auto-alt": "Подменяет TLS у YouTube и сдвигает номер",
        "general-fake-tls-auto-alt2": "Подменяет TLS у YouTube, сдвигает номер и режет начало",
        "general-fake-tls-auto-alt3": "Подменяет TLS у YouTube и режет начало",
        "general-simple-fake": "Подменяет TLS у YouTube",
        "general-simple-fake-alt": "Подменяет TLS у YouTube и сдвигает номер",
        "general-simple-fake-alt2": "Подменяет TLS у YouTube",
    ]

    private static let details: [String: String] = [
        "general": "В этой стратегии есть разрез. Подмены TLS нет.",
        "general-alt": "В этой стратегии есть fake-tls и разрез.",
        "general-alt2": "В этой стратегии есть разрез. Подмены TLS нет.",
        "general-alt3": "В этой стратегии есть fake-tls и подмена имени сайта.",
        "general-alt4": "В этой стратегии есть fake-tls, сдвиг номера и разрез.",
        "general-alt5": "Подмены TLS нет.",
        "general-alt6": "В этой стратегии есть разрез. Подмены TLS нет.",
        "general-alt7": "В этой стратегии есть разрез. Подмены TLS нет.",
        "general-alt8": "В этой стратегии есть fake-tls и сдвиг номера.",
        "general-alt9": "В этой стратегии подменяется имя сайта. Подмены TLS нет.",
        "general-alt10": "В этой стратегии есть fake-tls.",
        "general-alt11": "В этой стратегии есть fake-tls и разрез.",
        "general-alt12": "В этой стратегии есть fake-tls, подмена имени сайта и разрез.",
        "general-exp": "В этой стратегии есть fake-tls и обход QUIC.",
        "general-fake-tls-auto": "В этой стратегии есть fake-tls.",
        "general-fake-tls-auto-alt": "В этой стратегии есть fake-tls и сдвиг номера.",
        "general-fake-tls-auto-alt2": "В этой стратегии есть fake-tls, сдвиг номера и разрез.",
        "general-fake-tls-auto-alt3": "В этой стратегии есть fake-tls и разрез.",
        "general-simple-fake": "В этой стратегии есть fake-tls и подмена имени сайта.",
        "general-simple-fake-alt": "В этой стратегии есть fake-tls и сдвиг номера.",
        "general-simple-fake-alt2": "В этой стратегии есть fake-tls.",
    ]
}

struct HomeScreen: View {
    @ObservedObject var model: AppModel
    @State private var strategiesExpanded = false

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
            Rectangle()
                .fill(ZapretTheme.hairline)
                .frame(width: 1)
            rightColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.owner?.reloadDomainLists() }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            brand
            statusRow
            sitesSection
            Spacer(minLength: 8)
            Button {
                model.owner?.openDomains()
            } label: {
                Text("Списки сайтов")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ZapretTheme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Списки сайтов")
            .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: 210, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var brand: some View {
        HStack(spacing: 8) {
            HeroMoonMark(lit: false, side: 16)
            Text("ZAPRET")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(ZapretTheme.text)
                .lineLimit(1)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            HeroMoonMark(lit: false, side: 11)
            Text(statusWord)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
    }

    private var statusWord: String {
        if model.testing { return "ПОДБОР" }
        if model.busy && model.displayedRunning { return "ЗАПУСК" }
        if model.busy && !model.displayedRunning { return "ОСТАНОВКА" }
        if model.displayedRunning { return "ВКЛЮЧЕН" }
        return "ВЫКЛЮЧЕН"
    }

    private var statusColor: Color {
        if model.testing || model.busy { return ZapretTheme.accent }
        if model.displayedRunning { return ZapretTheme.text }
        return ZapretTheme.secondary
    }

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("САЙТЫ")
            siteRow(title: "Discord", mark: .discord, state: displayedReach(model.discordReach))
            siteRow(title: "YouTube", mark: .youtube, state: displayedReach(model.youtubeReach))
        }
    }

    private func siteRow(title: String, mark: ReachBrand, state: Reachability) -> some View {
        HStack(spacing: 8) {
            Group {
                switch mark {
                case .discord:
                    DiscordRowMark()
                case .youtube:
                    YouTubeRowMark()
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ZapretTheme.text)
                    .lineLimit(1)
                Text(reachText(state))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(reachColor(state))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ZapretTheme.hairline, lineWidth: 1)
        }
    }

    private func displayedReach(_ state: Reachability) -> Reachability {
        if !model.displayedRunning { return .unchecked }
        return state
    }

    private func reachText(_ state: Reachability) -> String {
        switch state {
        case .unchecked: return "не проверено"
        case .checking: return "проверяем"
        case .up: return "открывается"
        case .down: return "не открывается"
        }
    }

    private func reachColor(_ state: Reachability) -> Color {
        switch state {
        case .unchecked: return ZapretTheme.secondary
        case .checking: return ZapretTheme.secondary
        case .up: return ZapretTheme.running
        case .down: return Color(red: 0.92, green: 0.40, blue: 0.36)
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                gearMenu
            }
            VStack(alignment: .leading, spacing: 8) {
                strategyChoice("general-alt", fallback: "general (ALT)")
                strategyChoice("general", fallback: "general")
                strategyChoice("general-fake-tls-auto", fallback: "general (FAKE TLS AUTO)")
            }
            if !strategyPhrase.isEmpty {
                Text(strategyPhrase)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ZapretTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            moreControl
            if moreListVisible {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(moreStrategies) { strategy in
                            strategyChoice(strategy.id, fallback: strategy.name)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            if model.testing {
                HStack(spacing: 8) {
                    ProgressRing(fraction: model.progressFraction, side: 22)
                    Text("подбор стратегии")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ZapretTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func strategyChoice(_ id: String, fallback: String) -> some View {
        let name = model.strategies.first { $0.id == id }?.name ?? fallback
        let picked = model.selectedStrategy == id
        return Button {
            guard model.selectedStrategy != id else { return }
            if pinnedIDs.contains(id) {
                selectConcrete(id)
            } else {
                model.owner?.selectStrategy(id)
            }
        } label: {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(picked ? Color(red: 0.10, green: 0.08, blue: 0.05) : ZapretTheme.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(picked ? ZapretTheme.accent : Color.clear)
                }
                .overlay {
                    if !picked {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(ZapretTheme.hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
    }

    private var moreControl: some View {
        Button {
            if moreChipActive { return }
            strategiesExpanded.toggle()
        } label: {
            Text("ещё")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZapretTheme.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ZapretTheme.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
    }

    private var selected: Strategy? {
        model.strategies.first { $0.id == model.selectedStrategy }
    }

    private var headline: String {
        if let selected {
            return StrategyCopy.headline(for: selected)
        }
        return "Стратегия не выбрана"
    }

    private var strategyPhrase: String {
        guard let selected else { return headline }
        let behavior = StrategyCopy.headline(for: selected)
        if !behavior.isEmpty { return behavior }
        return StrategyCopy.detail(for: selected)
    }

    private var gearMenu: some View {
        Menu {
            Button(model.checkingUpdate ? "Проверка…" : "Проверить обновления") {
                model.owner?.checkForUpdatesNow()
            }
            .disabled(model.checkingUpdate || model.updating)
            if model.updateAvailable && !model.updateVersion.isEmpty {
                Button(model.updating ? "Установка…" : "Обновить до \(model.updateVersion)") {
                    model.owner?.installUpdate()
                }
                .disabled(!canInstallUpdate)
            }
            if !model.updateStatus.isEmpty {
                Button(model.updateStatus) {}
                    .disabled(true)
            }
            Divider()
            Button("Выход") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ZapretTheme.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Настройки")
    }

    private func selectConcrete(_ id: String) {
        guard model.selectedStrategy != id else { return }
        strategiesExpanded = false
        model.owner?.selectStrategy(id)
    }

    private func hasStrategy(_ id: String) -> Bool {
        model.strategies.contains { $0.id == id }
    }

    private var pinnedAltID: String? {
        let ids = model.strategies.map(\.id)
        if ids.contains("general-alt") { return "general-alt" }
        let alts = ids.filter { id in
            let key = id.lowercased()
            return key.hasPrefix("general-alt") && !key.contains("fake")
        }
        return alts.min { altOrder($0) < altOrder($1) }
    }

    private func altOrder(_ id: String) -> Int {
        let suffix = id.lowercased().dropFirst("general-alt".count)
        if suffix.isEmpty { return 0 }
        return Int(suffix) ?? Int.max
    }

    private var pinnedIDs: Set<String> {
        var ids = Set<String>()
        if let altID = pinnedAltID { ids.insert(altID) }
        if hasStrategy("general") { ids.insert("general") }
        if hasStrategy("general-fake-tls-auto") { ids.insert("general-fake-tls-auto") }
        return ids
    }

    private var moreChipActive: Bool {
        !pinnedIDs.contains(model.selectedStrategy)
    }

    private var moreListVisible: Bool {
        strategiesExpanded || moreChipActive
    }

    private var moreStrategies: [Strategy] {
        model.strategies.filter { !pinnedIDs.contains($0.id) }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(ZapretTheme.secondary)
            .lineLimit(1)
    }

    private var actionButton: some View {
        Button {
            if model.testing {
                model.owner?.stopTest()
            } else {
                model.owner?.toggleService()
            }
        } label: {
            Text(actionTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(actionFilled ? Color(red: 0.10, green: 0.08, blue: 0.05) : ZapretTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(actionFilled ? ZapretTheme.accent : Color.clear)
                }
                .overlay {
                    if !actionFilled {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ZapretTheme.hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(actionDisabled)
        .opacity(actionDisabled ? 0.45 : 1)
    }

    private var actionFilled: Bool {
        !model.displayedRunning && !model.testing
    }

    private var actionTitle: String {
        if model.testing { return "Остановить" }
        if model.displayedRunning { return "Выключить" }
        return "Включить"
    }

    private var actionDisabled: Bool {
        if model.testing { return model.cancellingTest }
        return model.busy
    }

    private var canInstallUpdate: Bool {
        model.updateAvailable && !model.updateVersion.isEmpty && !model.updating && !model.busy && !model.testing
    }
}

struct DomainsScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DomainListBlock(
                    title: "Свои сайты",
                    domains: model.userDomains,
                    draft: $model.domainDraft,
                    busy: model.busy,
                    onAdd: { model.owner?.addUserDomain() },
                    onRemove: { model.owner?.removeUserDomain($0) }
                )
                DomainListBlock(
                    title: "Исключения",
                    domains: model.excludeDomains,
                    draft: $model.excludeDraft,
                    busy: model.busy,
                    onAdd: { model.owner?.addExcludeDomain() },
                    onRemove: { model.owner?.removeExcludeDomain($0) }
                )
                if !model.domainNote.isEmpty {
                    Text(model.domainNote)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ZapretTheme.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.owner?.reloadDomainLists() }
    }
}

struct DomainListBlock: View {
    let title: String
    let domains: [String]
    @Binding var draft: String
    let busy: Bool
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZapretTheme.secondary)
                domainRows
                HStack(spacing: 8) {
                    TextField("example.com", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ZapretTheme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(ZapretTheme.insetFill)
                        }
                        .onSubmit { if !busy { onAdd() } }
                        .disabled(busy)
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(ZapretTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            }
        }
    }

    @ViewBuilder
    private var domainRows: some View {
        if domains.isEmpty {
            Text("Пусто")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ZapretTheme.tertiary)
                .padding(.vertical, 2)
        } else if domains.count > 5 {
            ScrollView { rows }
                .frame(height: 148)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(Array(domains.enumerated()), id: \.offset) { _, domain in
                HStack(spacing: 8) {
                    Text(domain)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(ZapretTheme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        onRemove(domain)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ZapretTheme.secondary)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Удалить")
                    .disabled(busy)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
            }
        }
    }
}

struct TestScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.testing {
                            Text(progressTitle)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(ZapretTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if !model.progressStrategy.isEmpty {
                                Text(model.progressDetail.isEmpty ? "Подготовка" : model.progressDetail)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(ZapretTheme.secondary)
                            }
                            if let fraction = model.progressFraction {
                                ProgressView(value: fraction)
                                    .tint(ZapretTheme.accent)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(ZapretTheme.accent)
                            }
                        } else {
                            Text("Подбор стратегии")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(ZapretTheme.text)
                            Text("Проверит доступные варианты и подскажет лучший.")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(ZapretTheme.secondary)
                        }
                    }
                }

                if !model.testRows.isEmpty {
                    GlassCard(padding: 10) {
                        resultList
                    }
                }

                if !statusLine.isEmpty {
                    Text(statusLine)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(model.testBestNames.isEmpty ? ZapretTheme.secondary : ZapretTheme.accent)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if model.testing {
                        Button(model.cancellingTest ? "Остановка…" : "Остановить") {
                            model.owner?.stopTest()
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(model.cancellingTest)
                    } else if !model.testBestNames.isEmpty {
                        Button("Применить") {
                            model.owner?.applyTestedStrategy()
                        }
                        .buttonStyle(QuietButtonStyle(prominent: true))
                        .disabled(model.busy)
                        if model.testBestNames.count > 1, let first = model.testBestNames.first {
                            Text("Будет выбрана «\(first)»")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(ZapretTheme.secondary)
                        }
                        Button("Подобрать снова") {
                            model.owner?.beginTest()
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(model.busy)
                    } else {
                        Button("Подобрать стратегию") {
                            model.owner?.beginTest()
                        }
                        .buttonStyle(QuietButtonStyle(prominent: true))
                        .disabled(model.busy)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var progressTitle: String {
        if !model.progressStrategy.isEmpty { return model.progressStrategy }
        if !model.progressDetail.isEmpty { return model.progressDetail }
        return "Подготовка"
    }

    private var statusLine: String {
        if model.testing { return "" }
        if model.testSummary.contains("Применена:") {
            return model.testSummary.split(separator: "\n").last.map(String.init) ?? ""
        }
        if !model.testBestNames.isEmpty { return "" }
        return model.testSummary
    }

    @ViewBuilder
    private var resultList: some View {
        if model.testRows.count > 6 {
            ScrollView { rows }
                .frame(height: 220)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(model.testRows) { row in
                testRow(row)
            }
        }
    }

    private func testRow(_ row: StrategyTestRow) -> some View {
        let best = !model.testing && model.testBestNames.contains(row.name)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 13, weight: best ? .medium : .regular))
                    .foregroundStyle(best ? ZapretTheme.accent : ZapretTheme.text)
                    .lineLimit(1)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(ZapretTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !row.score.isEmpty {
                Text(row.score)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(best ? ZapretTheme.accent : ZapretTheme.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if best {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ZapretTheme.pillSelected.opacity(0.55))
            }
        }
    }
}
