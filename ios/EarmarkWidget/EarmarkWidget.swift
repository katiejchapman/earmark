import SwiftUI
import WidgetKit
import AppIntents
import UIKit

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
    @Environment(\.widgetRenderingMode) private var renderingMode
    let state: WidgetSnapshot
    let date: Date
    private var small: Bool { family == .systemSmall }
    private static let progressPixel: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
        UIColor(red: 0.72, green: 0.32, blue: 0.50, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    private static let tintedScreenPixel: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
        UIColor(red: 0.12, green: 0.17, blue: 0.11, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    private var lcdColors: [Color] {
        [Color(red: 0.69, green: 0.74, blue: 0.64), Color(red: 0.60, green: 0.65, blue: 0.55)]
    }
    private let pink = Color(red: 0.87, green: 0.64, blue: 0.75)
    private var ink: Color { state.dark ? Color.white.opacity(0.9) : Color(red: 0.24, green: 0.27, blue: 0.25) }
    private var metal: [Color] { state.dark ? [Color(white: 0.58), Color(red: 0.32, green: 0.34, blue: 0.38), Color(white: 0.49), Color(white: 0.25)] : [Color(white: 0.94), Color(red: 0.75, green: 0.77, blue: 0.74), Color(white: 0.88), Color(red: 0.65, green: 0.68, blue: 0.65)] }
    var body: some View {
        GeometryReader { geometry in
            let layout = WidgetStereoLayout(size: geometry.size, small: small)
            VStack(spacing: layout.gap) {
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
                .foregroundStyle(renderingMode == .fullColor ? Color(red: 0.20, green: 0.27, blue: 0.17) : Color.primary)
                .padding(.horizontal, 9).frame(maxWidth: .infinity).frame(height: layout.lcd.height, alignment: .leading)
                .background {
                    if renderingMode == .fullColor {
                        RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: lcdColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        Image(uiImage: Self.tintedScreenPixel).resizable().preserveWidgetColor().clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LinearGradient(colors: [.black.opacity(0.5), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
                VStack(spacing: 3) {
                    GeometryReader { bar in
                        let ratio = state.duration > 0 ? min(1, state.position(at: date) / state.duration) : 0
                        Capsule().fill(.black.opacity(0.4))
                        Image(uiImage: Self.progressPixel).resizable().preserveWidgetColor().frame(width: bar.size.width * ratio).clipShape(Capsule())
                    }.frame(height: 6)
                    HStack {
                        Text(time(state.position(at: date))); Spacer()
                        Text("−" + time(max(0, state.duration - state.position(at: date))))
                    }.font(.system(size: 9, design: .monospaced)).monospacedDigit()
                }
                .frame(height: layout.time.height)
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    transport("«15", action: "back")
                    transport(state.playing ? "Ⅱ" : "▶", action: "toggle", main: true)
                    transport("15»", action: "forward")
                    Spacer(minLength: 0)
                }.frame(height: layout.controls.height)
                HStack(spacing: 9) {
                    Circle().fill(state.playing ? Color.red : Color(red: 0.24, green: 0.08, blue: 0.11)).frame(width: 6, height: 6)
                        .shadow(color: state.playing ? .red.opacity(0.85) : .clear, radius: 3).frame(width: 14)
                    Canvas { context, size in
                        for x in stride(from: 1.0, to: size.width, by: 4) {
                            for y in stride(from: 1.0, to: size.height, by: 4) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.black.opacity(0.65)))
                            }
                        }
                    }.background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 5)).clipShape(RoundedRectangle(cornerRadius: 5))
                    auxiliary("sleep", action: "sleep")
                }.frame(height: layout.footer.height)
            }
            .padding(.horizontal, layout.inset).padding(.vertical, 11)
            .frame(width: geometry.size.width, height: geometry.size.height)

        }
        .foregroundStyle(ink)
        .environment(\.colorScheme, state.dark ? .dark : .light)
        .unredacted()
        .containerBackground(for: .widget) { LinearGradient(colors: metal, startPoint: .topLeading, endPoint: .bottomTrailing) }
        .widgetURL(url("open"))
    }
    private func url(_ action: String) -> URL { URL(string: "earmark://widget/" + action)! }
    private func time(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.isFinite ? seconds : 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    private func transport(_ text: String, action: String, main: Bool = false) -> some View {
        Button(intent: StereoPlaybackIntent(action: action)) {
            Text(text).font(.system(size: main ? 12 : 9, weight: .semibold, design: .rounded))
                .frame(width: main ? 30 : 24, height: main ? 30 : 24)
                .foregroundStyle(main ? Color(red: 0.35, green: 0.20, blue: 0.28) : Color.white)
                .background(main ? pink : Color(white: 0.28), in: Circle())
                .overlay(Circle().strokeBorder(main ? Color(red: 0.72, green: 0.47, blue: 0.60) : Color(white: 0.65), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(action == "toggle" ? (state.playing ? "Pause" : "Play") : "Skip 15 seconds")
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
        .containerBackgroundRemovable(false)
        .description("Your mini stereo. Tap to open earmark and control your audio.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private extension Image {
    @ViewBuilder func preserveWidgetColor() -> some View {
        if #available(iOS 18.0, *) { self.widgetAccentedRenderingMode(.fullColor) }
        else { self }
    }
}
