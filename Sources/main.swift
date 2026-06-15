import SwiftUI
import AppKit

// MARK: - Model

struct Limit {
    var utilization: Double
    var windowMinutes: Int?
    var resetsAt: Date?
}

struct TokenTotals {
    var input = 0
    var cachedInput = 0
    var output = 0
    var reasoning = 0
    var total: Int { input + output }

    mutating func add(_ usage: [String: Any]) {
        func n(_ k: String) -> Int {
            (usage[k] as? Int) ?? Int((usage[k] as? Double) ?? 0)
        }
        input += n("input_tokens")
        cachedInput += n("cached_input_tokens")
        output += n("output_tokens")
        reasoning += n("reasoning_output_tokens")
    }
}

struct ModelUsage: Identifiable {
    var model: String
    var session = TokenTotals()
    var today = TokenTotals()
    var allTime = TokenTotals()
    var id: String { model }
}

struct UsageBreakdown {
    var session = TokenTotals()
    var today = TokenTotals()
    var allTime = TokenTotals()
    var models: [ModelUsage] = []
}

struct Usage {
    var session: Limit?
    var weekAll: Limit?
    var planType: String?
    var breakdown: UsageBreakdown?
    var lastUpdated = Date()
    var error: String?
    var loaded = false
}

struct TokenEvent {
    var timestamp: Date
    var model: String
    var usage: [String: Any]
}

// MARK: - Source (local Codex session logs)

enum UsageSource {
    static let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    static func parseDate(_ s: String?) -> Date? {
        guard var s else { return nil }
        if let re = try? NSRegularExpression(pattern: "(\\.\\d{3})\\d+") {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func epochDate(_ any: Any?) -> Date? {
        if let i = any as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let d = any as? Double { return Date(timeIntervalSince1970: d) }
        return nil
    }

    static func limit(_ any: Any?) -> Limit? {
        guard let d = any as? [String: Any] else { return nil }
        let pct = (d["used_percent"] as? Double) ?? Double((d["used_percent"] as? Int) ?? -1)
        guard pct >= 0 else { return nil }
        let window = (d["window_minutes"] as? Int) ?? Int((d["window_minutes"] as? Double) ?? 0)
        return Limit(
            utilization: pct,
            windowMinutes: window > 0 ? window : nil,
            resetsAt: epochDate(d["resets_at"])
        )
    }

    static func shortModel(_ m: String?) -> String {
        guard var s = m, !s.isEmpty else { return "unknown" }
        if s.hasPrefix("openai/") { s = String(s.dropFirst("openai/".count)) }
        return s
    }

    static func jsonlFiles() -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    static func fetch() async -> Usage {
        var out = Usage()
        var events: [TokenEvent] = []
        var latestRateLimitAt = Date.distantPast

        for file in jsonlFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var model = "unknown"

            text.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }

                let type = o["type"] as? String
                if type == "session_meta", let payload = o["payload"] as? [String: Any] {
                    model = shortModel(payload["model"] as? String)
                    return
                }
                if type == "turn_context", let payload = o["payload"] as? [String: Any] {
                    model = shortModel(payload["model"] as? String)
                    return
                }

                guard type == "event_msg",
                      let payload = o["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["last_token_usage"] as? [String: Any]
                else { return }

                let ts = parseDate(o["timestamp"] as? String) ?? Date.distantPast

                if let rate = payload["rate_limits"] as? [String: Any], ts >= latestRateLimitAt {
                    latestRateLimitAt = ts
                    out.session = limit(rate["primary"])
                    out.weekAll = limit(rate["secondary"])
                    out.planType = rate["plan_type"] as? String
                }

                events.append(TokenEvent(timestamp: ts, model: model, usage: usage))
            }
        }

        var breakdown = UsageBreakdown()
        var perModel: [String: ModelUsage] = [:]
        let todayStart = Calendar.current.startOfDay(for: Date())
        var currentSessionStart = Date().addingTimeInterval(-5 * 3600)
        if let session = out.session, let reset = session.resetsAt {
            let minutes = Double(session.windowMinutes ?? 300)
            currentSessionStart = reset.addingTimeInterval(-minutes * 60)
        }

        for event in events {
            let ts = event.timestamp
            let inToday = ts >= todayStart
            let inSession = ts >= currentSessionStart
            var m = perModel[event.model] ?? ModelUsage(model: event.model)

            breakdown.allTime.add(event.usage)
            m.allTime.add(event.usage)
            if inToday {
                breakdown.today.add(event.usage)
                m.today.add(event.usage)
            }
            if inSession {
                breakdown.session.add(event.usage)
                m.session.add(event.usage)
            }
            perModel[event.model] = m
        }

        breakdown.models = perModel.values
            .filter { $0.allTime.total > 0 }
            .sorted { $0.allTime.total > $1.allTime.total }
        out.breakdown = breakdown
        if events.isEmpty {
            out.error = "No Codex token-count events found yet."
        }
        out.loaded = true
        out.lastUpdated = Date()
        return out
    }
}

// MARK: - Monitor

@MainActor
final class UsageMonitor: ObservableObject {
    @Published var usage = Usage()
    @Published var isRefreshing = false

    static let interval: TimeInterval = 5 * 60
    static let minGap: TimeInterval = 30
    private var timer: Timer?
    private var lastAttempt = Date.distantPast

    init() {
        refresh(force: true)
        let t = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastAttempt) < Self.minGap { return }
        lastAttempt = now
        isRefreshing = true
        Task {
            self.usage = await UsageSource.fetch()
            self.isRefreshing = false
        }
    }
}

// MARK: - Color

func ringColor(_ pct: Double) -> Color {
    switch pct {
    case ..<50: return .green
    case ..<70: return .yellow
    case ..<90: return .orange
    default: return .red
    }
}

// MARK: - Menu-bar ring (Core Graphics -> NSImage)

func makeRingImage(percent: Double, height: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: height, height: height))
    image.lockFocus()
    defer { image.unlockFocus() }

    let lineWidth = max(2, height * 0.16)
    let inset = lineWidth / 2 + 1
    let rect = NSRect(x: inset, y: inset, width: height - inset * 2, height: height - inset * 2)

    let track = NSBezierPath(ovalIn: rect)
    track.lineWidth = lineWidth
    NSColor.tertiaryLabelColor.setStroke()
    track.stroke()

    let center = NSPoint(x: height / 2, y: height / 2)
    let radius = rect.width / 2
    let start: CGFloat = 90
    let end = start - CGFloat(360 * min(max(percent / 100, 0), 1))
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    NSColor(ringColor(percent)).setStroke()
    arc.stroke()

    image.isTemplate = false
    return image
}

// MARK: - Popover

struct PercentRow: View {
    let title: String
    let limit: Limit?

    private func resetText(_ d: Date?) -> String? {
        guard let d else { return nil }
        let f = DateFormatter()
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = "h:mm a"
            return "resets \(f.string(from: d))"
        }
        f.dateFormat = "MMM d, h:mm a"
        return "resets \(f.string(from: d))"
    }

    var body: some View {
        let pct = limit?.utilization ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(limit == nil ? "-" : "\(Int(pct.rounded()))%")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(limit == nil ? .secondary : ringColor(pct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(ringColor(pct))
                        .frame(width: geo.size.width * min(max(pct / 100, 0), 1))
                }
            }
            .frame(height: 6)
            if let r = resetText(limit?.resetsAt) {
                Text(r).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

func fmtTokens(_ n: Int) -> String {
    if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1_000_000_000) }
    if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

struct TokenGrid: View {
    let breakdown: UsageBreakdown

    private func columnHeader() -> some View {
        GridRow {
            Text("").gridColumnAlignment(.leading)
            Text("5h"); Text("Today"); Text("All")
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func typeRow(_ label: String, _ pick: (TokenTotals) -> Int, bold: Bool = false) -> some View {
        GridRow {
            Text(label).gridColumnAlignment(.leading)
                .foregroundStyle(bold ? Color.primary : Color.secondary)
            Text(fmtTokens(pick(breakdown.session)))
            Text(fmtTokens(pick(breakdown.today)))
            Text(fmtTokens(pick(breakdown.allTime)))
        }
        .font(.caption.weight(bold ? .semibold : .regular)).monospacedDigit()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tokens").font(.subheadline.weight(.medium))
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 5) {
                columnHeader()
                typeRow("Input", { $0.input })
                typeRow("Cached", { $0.cachedInput })
                typeRow("Output", { $0.output })
                typeRow("Reasoning", { $0.reasoning })
                Divider()
                typeRow("Total", { $0.total }, bold: true)
            }

            if !breakdown.models.isEmpty {
                Divider()
                Text("By model (total tokens)").font(.subheadline.weight(.medium))
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 5) {
                    columnHeader()
                    ForEach(breakdown.models) { m in
                        GridRow {
                            Text(m.model).gridColumnAlignment(.leading).foregroundStyle(.secondary)
                            Text(fmtTokens(m.session.total))
                            Text(fmtTokens(m.today.total))
                            Text(fmtTokens(m.allTime.total))
                        }
                        .font(.caption).monospacedDigit()
                    }
                }
            }
        }
    }
}

struct PopoverView: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        let u = monitor.usage
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text("Codex Usage").font(.headline)
                if let plan = u.planType, !plan.isEmpty {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if monitor.isRefreshing { ProgressView().controlSize(.small) }
            }

            if !u.loaded {
                Text("Loading...").font(.callout).foregroundStyle(.secondary)
            } else {
                if let err = u.error {
                    Text(err).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PercentRow(title: "Current session", limit: u.session)
                    PercentRow(title: "Current week", limit: u.weekAll)
                }
                if let b = u.breakdown {
                    Divider()
                    TokenGrid(breakdown: b)
                }
            }

            Divider()
            HStack {
                Text("Updated \(u.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { monitor.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh now")
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 290)
        .onAppear { monitor.refresh() }
    }
}

// MARK: - App

@main
struct CodexUsageBarApp: App {
    @StateObject private var monitor = UsageMonitor()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: monitor)
        } label: {
            let pct = monitor.usage.session?.utilization ?? 0
            Image(nsImage: makeRingImage(percent: pct))
            Text("\(Int(pct.rounded()))%")
        }
        .menuBarExtraStyle(.window)
    }
}
