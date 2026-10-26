import SwiftUI
import WidgetKit
import AppIntents

private struct StereoEntry: TimelineEntry {
    let date: Date
    let state: WidgetSnapshot
}
enum StereoAppearance: String, AppEnum {
    case matchApp, dark, light
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Appearance"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.matchApp: "Match app", .dark: "Dark", .light: "Light"]
}
struct StereoConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Stereo appearance"
    @Parameter(title: "Appearance", default: .matchApp) var appearance: StereoAppearance
}
private struct StereoProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StereoEntry { StereoEntry(date: Date(), state: .empty) }
    private func state(for configuration: StereoConfiguration) -> WidgetSnapshot {
        var state = WidgetSnapshot.read()
        if configuration.appearance != .matchApp { state.dark = configuration.appearance == .dark }
        return state
    }
    func snapshot(for configuration: StereoConfiguration, in context: Context) async -> StereoEntry {
        StereoEntry(date: Date(), state: state(for: configuration))
    }
    func timeline(for configuration: StereoConfiguration, in context: Context) async -> Timeline<StereoEntry> {
        let now = Date(), state = state(for: configuration)
        var dates = (0..<(state.playing ? 60 : 1)).map { now.addingTimeInterval(Double($0) * 60) }
        if let deadline = state.sleepDeadline, deadline > now { dates.append(deadline) }
        let entries = dates.sorted().map { StereoEntry(date: $0, state: state) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(state.playing ? 3600 : 900)))
    }
}

struct StereoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let state: WidgetSnapshot
    let date: Date
    private var small: Bool { family == .systemSmall }
    private let pink = Color(red: 0.87, green: 0.64, blue: 0.75)
    private var ink: Color { state.dark ? Color.white.opacity(0.9) : Color(red: 0.24, green: 0.27, blue: 0.25) }
    private var metal: [Color] { state.dark ? [Color(white: 0.58), Color(red: 0.32, green: 0.34, blue: 0.38), Color(white: 0.49), Color(white: 0.25)] : [Color(white: 0.94), Color(red: 0.75, green: 0.77, blue: 0.74), Color(white: 0.88), Color(red: 0.65, green: 0.68, blue: 0.65)] }
    var body: some View {
        GeometryReader { geometry in
            let layout = WidgetStereoLayout(size: geometry.size, small: small)
            VStack(spacing: layout.gap) {
                HStack(spacing: 0) {
                    ForEach(0..<11, id: \.self) { i in
                        if i > 0 { Spacer(minLength: 1) }
                        Image("RoundRhinestone").resizable().scaledToFit().frame(width: small ? 7 : 9, height: small ? 7 : 9)
                    }
                }.frame(height: layout.jewels.height).padding(.horizontal, small ? 5 : 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title).font(.system(size: small ? 12 : 14, weight: .semibold, design: .monospaced)).lineLimit(1)
                    HStack(spacing: 3) {
                        Text(state.folder).lineLimit(1)
                        Spacer(minLength: 0)
                        if let deadline = state.sleepDeadline, deadline > date {
                            (Text("sleep ") + Text(deadline, style: .timer)).monospacedDigit().fixedSize()
                        } else if state.sleepDeadline == nil, state.sleepRemaining > 0 {
                            Text("sleep " + time(state.sleepRemaining.rounded(.up))).monospacedDigit().fixedSize()
                        }
                    }.font(.system(size: small ? 7 : 9, design: .monospaced))
                }
                .foregroundStyle(Color(red: 0.20, green: 0.27, blue: 0.17))
                .padding(.horizontal, 9).frame(maxWidth: .infinity).frame(height: layout.lcd.height, alignment: .leading)
                .background(LinearGradient(colors: [Color(red: 0.69, green: 0.74, blue: 0.64), Color(red: 0.60, green: 0.65, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LinearGradient(colors: [.black.opacity(0.5), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
                VStack(spacing: 3) {
                    GeometryReader { bar in
                        let ratio = state.duration > 0 ? min(1, state.position(at: date) / state.duration) : 0
                        Capsule().fill(.black.opacity(0.4))
                        Capsule().fill(Color(white: 0.83)).frame(width: bar.size.width * ratio)
                        Circle().fill(LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 8, height: 8).offset(x: max(0, min(bar.size.width - 8, bar.size.width * ratio - 4)), y: -2)
                    }.frame(height: 4)
                    HStack {
                        Text(time(state.position(at: date))); Spacer()
                        Text("−" + time(max(0, state.duration - state.position(at: date))))
                    }.font(.system(size: 8, design: .monospaced)).monospacedDigit()
                }
                .frame(height: layout.time.height)
                HStack(spacing: 4) {
                    auxiliary("sleep", action: "sleep"); Spacer(minLength: 0)
                    transport("«15", action: "back")
                    transport(state.playing ? "Ⅱ" : "▶", action: "toggle", main: true)
                    transport("15»", action: "forward")
                    Spacer(minLength: 0); auxiliary("reset", action: "reset")
                }.frame(height: layout.controls.height)
                Color.clear.frame(height: layout.decoration.height)
                HStack(spacing: 9) {
                    Circle().fill(state.loaded ? Color.red : .clear).frame(width: 6, height: 6)
                        .shadow(color: state.loaded ? .red.opacity(0.85) : .clear, radius: 3).frame(width: 14)
                    Canvas { context, size in
                        for x in stride(from: 1.0, to: size.width, by: 4) {
                            for y in stride(from: 1.0, to: size.height, by: 4) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.black.opacity(0.65)))
                            }
                        }
                    }.background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 5)).clipShape(RoundedRectangle(cornerRadius: 5))
                    Link(destination: url("decorate")) {
                        StickerSheetIcon().frame(width: 18, height: 18)
                    }.accessibilityLabel("Open sticker sheet")
                }.frame(height: layout.footer.height)
            }
            .padding(.horizontal, layout.inset).padding(.vertical, 11)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay {
                ForEach(state.decorations.visible(in: geometry.size, obstacles: layout.protectedRects)) { gem in
                    Image(gem.asset).resizable().scaledToFit().frame(width: gem.size, height: gem.size)
                        .rotationEffect(.degrees(gem.rotation))
                        .position(x: geometry.size.width * gem.x, y: geometry.size.height * gem.y)
                }.allowsHitTesting(false)
            }
        }
        .foregroundStyle(ink)
        .containerBackground(for: .widget) { LinearGradient(colors: metal, startPoint: .topLeading, endPoint: .bottomTrailing) }
        .widgetURL(url("open"))
    }
    private func url(_ action: String) -> URL { URL(string: "earmark://widget/" + action)! }
    private func time(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.isFinite ? seconds : 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    private func transport(_ text: String, action: String, main: Bool = false) -> some View {
        Link(destination: url(action)) {
            Text(text).font(.system(size: main ? 12 : 9, weight: .semibold, design: .rounded))
                .frame(width: main ? 30 : 24, height: main ? 30 : 24)
                .foregroundStyle(main ? Color(red: 0.35, green: 0.20, blue: 0.28) : Color.white)
                .background(main ? pink : Color(white: 0.28), in: Circle())
                .overlay(Circle().strokeBorder(main ? Color(red: 0.72, green: 0.47, blue: 0.60) : Color(white: 0.65), lineWidth: 1))
        }.accessibilityLabel(action == "toggle" ? "Open player and play or pause" : "Open player and skip 15 seconds")
    }
    private func auxiliary(_ text: String, action: String) -> some View {
        Link(destination: url(action)) {
            Text(text).font(.system(size: small ? 7 : 8, design: .rounded)).frame(width: small ? 24 : 34, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ink.opacity(0.7)))
        }
    }
}

@main
struct EarmarkStereoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshot.kind, intent: StereoConfiguration.self, provider: StereoProvider()) { entry in
            StereoWidgetView(state: entry.state, date: entry.date)
        }
        .configurationDisplayName("earmark")
        .description("Your mini stereo. Tap to open earmark and control your audio.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
