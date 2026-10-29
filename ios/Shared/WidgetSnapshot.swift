import Foundation

struct WidgetSnapshot: Codable, Equatable {
    static let groupID = "group.com.katiechapman.earmark"
    static let kind = "EarmarkStereo"
    var title: String
    var folder: String
    var position: Double
    var duration: Double
    var playing: Bool
    var loaded: Bool
    var dark: Bool
    var updated: Date
    var sleepDeadline: Date?
    var sleepRemaining: Double = 0
    var decorations: WidgetDecorations = .empty
    static var empty: Self { Self(title: "earmark", folder: "", position: 0, duration: 0, playing: false, loaded: false, dark: true, updated: Date()) }
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("widget-state.json")
    }
    static func read() -> Self {
        guard let file, let data = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return state
    }
    func write(to file: URL) throws {
        try JSONEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func position(at date: Date) -> Double {
        let until = sleepDeadline.map { min(date, $0) } ?? date
        let elapsed = playing ? max(0, until.timeIntervalSince(updated)) : 0
        return duration > 0 ? min(duration, max(0, position + elapsed)) : max(0, position)
    }
}

struct WidgetGem: Codable, Equatable, Identifiable {
    var id: UUID
    var asset: String
    var x: Double
    var y: Double
    var size: Double
    var rotation: Double
    func footprint(in size: CGSize) -> CGRect {
        let angle = rotation * .pi / 180
        let side = self.size * (abs(cos(angle)) + abs(sin(angle)))
        return CGRect(x: x * size.width - side / 2, y: y * size.height - side / 2, width: side, height: side)
    }
}
struct WidgetDecorations: Codable, Equatable {
    var width: Double
    var height: Double
    var gems: [WidgetGem]
    static var empty: Self { Self(width: 362, height: 365, gems: []) }
    // Keep a representative subset of the saved sheet, enlarged into the free metal band.
    func widgetGems(in size: CGSize, band: CGRect) -> [WidgetGem] {
        let count = min(size.width < 200 ? 2 : 3, gems.count)
        guard count > 0 else { return [] }
        return gems.prefix(count).enumerated().map { index, original in
            var gem = original
            let rotatedScale = abs(cos(gem.rotation * .pi / 180)) + abs(sin(gem.rotation * .pi / 180))
            gem.size = min(26, band.height / max(1, rotatedScale))
            gem.x = (band.minX + band.width * Double(index + 1) / Double(count + 1)) / size.width
            gem.y = band.midY / size.height
            return gem
        }
    }
    // Preserve relative positions and rotation, shrink uniformly, and omit only
    // gems whose rotated artwork would cover a widget control or another gem.
    func visible(in size: CGSize, obstacles: [CGRect]) -> [WidgetGem] {
        guard width.isFinite, height.isFinite, width > 0, height > 0, size.width > 0, size.height > 0 else { return [] }
        let scale = min(1, size.width / width, size.height / height)
        var result: [WidgetGem] = []
        for original in gems {
            guard [original.x, original.y, original.size, original.rotation].allSatisfy(\.isFinite) else { continue }
            var gem = original; gem.size *= scale
            let rect = gem.footprint(in: size)
            guard gem.size >= 6, CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6).contains(rect),
                  !obstacles.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(rect) }),
                  !result.contains(where: { $0.footprint(in: size).insetBy(dx: -2, dy: -2).intersects(rect) }) else { continue }
            result.append(gem)
        }
        return result
    }
}
struct WidgetStereoLayout {
    let inset: Double
    let gap: Double
    let jewels: CGRect
    let lcd: CGRect
    let time: CGRect
    let controls: CGRect
    let decoration: CGRect
    let footer: CGRect
    var protectedRects: [CGRect] { [jewels, lcd, time, controls, footer] }
    init(size: CGSize, small: Bool) {
        inset = small ? 12 : 16; gap = small ? 4 : 5
        let jewelHeight = small ? 7.0 : 9.0, footerHeight = small ? 12.0 : 15.0
        let bandHeight = 27.0, timeHeight = 17.0, controlsHeight = 30.0
        let lcdHeight = max(24, size.height - 22 - gap * 5 - jewelHeight - timeHeight - controlsHeight - bandHeight - footerHeight)
        let width = max(0, size.width - inset * 2)
        jewels = CGRect(x: inset, y: 11, width: width, height: jewelHeight)
        lcd = CGRect(x: inset, y: jewels.maxY + gap, width: width, height: lcdHeight)
        time = CGRect(x: inset, y: lcd.maxY + gap, width: width, height: timeHeight)
        controls = CGRect(x: inset, y: time.maxY + gap, width: width, height: controlsHeight)
        decoration = CGRect(x: inset, y: controls.maxY + gap, width: width, height: bandHeight)
        footer = CGRect(x: inset, y: decoration.maxY + gap, width: width, height: footerHeight)
    }
}
