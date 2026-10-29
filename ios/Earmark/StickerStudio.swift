import SwiftUI
import UIKit
import Combine

struct GemChoice: Identifiable {
    let shape: String
    let color: String
    var id: String { "Gem_\(shape.replacingOccurrences(of: "-", with: "_"))_\(color)" }
    var label: String { "\(color) \(shape.replacingOccurrences(of: "-", with: " ")) gem" }
    // Interleave shapes and colors so every page feels like a mixed sticker sheet.
    static let all: [GemChoice] = (0..<48).map { index in
        let shapes = ["heart", "star", "flower", "moon", "diamond", "butterfly", "round", "petal-flower"]
        let colors = ["green", "blue", "pink", "yellow", "purple", "silver"]
        return GemChoice(shape: shapes[index % 8], color: colors[(index / 8 + index % 8) % 6])
    }

}

struct PlacedGem: Identifiable, Codable, Equatable {
    var id = UUID()
    var asset: String
    var x: Double
    var y: Double
    var size: Double
    var rotation: Double = 0

    mutating func constrain(to size: CGSize) {
        self.size = min(120, max(8, self.size))
        rotation = (rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let radians = rotation * .pi / 180
        let inset = self.size / 2 * (abs(cos(radians)) + abs(sin(radians))) + 4
        let horizontal = min(0.49, inset / max(1, size.width))
        let vertical = min(0.49, inset / max(1, size.height))
        x = min(1 - horizontal, max(horizontal, x))
        y = min(1 - vertical, max(vertical, y))
    }
}

@MainActor
final class StickerStudioStore: ObservableObject {
    @Published private(set) var saved: [PlacedGem]
    @Published var draft: [PlacedGem]
    @Published private(set) var editing = false
    @Published var page = 0
    @Published var pageSwipe: Double = 0
    @Published var selectedID: UUID?
    @Published var activeID: UUID?
    @Published var error: String?
    private let file: URL
    private var layoutSize: CGSize?
    private var blocked: [CGRect] = []
    private var pristine = true
    private var unreadable = false

    static var defaults: [PlacedGem] {
        [PlacedGem(asset: "Gem_heart_pink", x: 0.20, y: 0.80, size: 22, rotation: -14),
         PlacedGem(asset: "Gem_flower_blue", x: 0.63, y: 0.81, size: 20, rotation: 17),
         PlacedGem(asset: "Gem_diamond_pink", x: 0.83, y: 0.79, size: 20, rotation: 12)]
    }

    init(file: URL) {
        self.file = file
        var initial = Self.defaults
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let decoded = try JSONDecoder().decode([PlacedGem].self, from: Data(contentsOf: file))
                let assets = Set(GemChoice.all.map(\.id))
                guard Set(decoded.map(\.id)).count == decoded.count,
                      decoded.allSatisfy({ assets.contains($0.asset) && $0.x.isFinite && $0.y.isFinite && $0.size.isFinite && $0.rotation.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) && (8...120).contains($0.size) }) else { throw CocoaError(.fileReadCorruptFile) }
                initial = decoded; pristine = false
            } catch { unreadable = true }
        }
        saved = initial; draft = initial
    }

    var widgetDecorations: WidgetDecorations {
        let size = layoutSize ?? CGSize(width: 362, height: 365)
        return WidgetDecorations(width: size.width, height: size.height, gems: saved.map {
            WidgetGem(id: $0.id, asset: $0.asset, x: $0.x, y: $0.y, size: $0.size, rotation: $0.rotation)
        })
    }
    var visible: [PlacedGem] { editing ? draft : saved }
    var pageCount: Int { (GemChoice.all.count + 4) / 5 }
    var choices: [GemChoice] { Array(GemChoice.all.dropFirst(page * 5).prefix(5)) }

    func begin() { draft = saved; selectedID = nil; editing = true }
    func finish() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if unreadable, FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("decorations-unreadable-\(UUID().uuidString).json"))
            }
            try JSONEncoder().encode(draft).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saved = draft; editing = false; selectedID = nil; activeID = nil; pristine = false; unreadable = false; error = nil
        } catch { self.error = "Couldn’t save decorations: \(error.localizedDescription)" }
    }
    func changePage(_ delta: Int) { page = min(pageCount - 1, max(0, page + delta)) }
    // Collision checks include the rotated artwork, a minimal gap, and every protected control.
    private func footprint(_ gem: PlacedGem, in size: CGSize) -> CGRect {
        let radians = gem.rotation * .pi / 180
        let side = gem.size * (abs(cos(radians)) + abs(sin(radians)))
        return CGRect(x: gem.x * size.width - side / 2, y: gem.y * size.height - side / 2, width: side, height: side)
    }
    func canPlace(_ gem: PlacedGem, among others: [PlacedGem]? = nil) -> Bool {
        guard let size = layoutSize else { return true }
        let rect = footprint(gem, in: size)
        let surface = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), cornerRadius: 28)
        guard [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].allSatisfy(surface.contains),
              !blocked.contains(where: { $0.insetBy(dx: -0.25, dy: -0.25).intersects(rect) }) else { return false }
        return !(others ?? draft).contains { $0.id != gem.id && footprint($0, in: size).insetBy(dx: -0.25, dy: -0.25).intersects(rect) }
    }
    // Subpixel swept movement prevents tunnelling through a thin protected area.
    // Resolve translation per axis so a gem can slide along the edge it reaches.
    func limitedMotion(from original: PlacedGem, to target: PlacedGem) -> PlacedGem {
        guard let size = layoutSize, canPlace(original) else { return original }
        let dx = (target.x - original.x) * size.width
        let dy = (target.y - original.y) * size.height
        let ds = target.size - original.size
        let dr = target.rotation - original.rotation
        guard [dx, dy, ds, dr].allSatisfy(\.isFinite) else { return original }
        let steps = max(1, Int(ceil(max(abs(dx), abs(dy), abs(ds), abs(dr)) / 0.75)))
        var safe = original
        for _ in 0..<steps {
            var candidate = safe; candidate.x += dx / Double(steps) / size.width
            if canPlace(candidate) { safe = candidate }
            candidate = safe; candidate.y += dy / Double(steps) / size.height
            if canPlace(candidate) { safe = candidate }
            candidate = safe; candidate.size = min(120, max(8, candidate.size + ds / Double(steps)))
            candidate.rotation += dr / Double(steps)
            if canPlace(candidate) { safe = candidate }
        }
        return safe
    }
    func initialPlacement(_ gem: PlacedGem) -> PlacedGem? {
        nearestPlacement(gem, among: draft, mayShrink: false)
    }
    @discardableResult func place(_ gem: PlacedGem) -> Bool {
        guard editing, canPlace(gem) else { return false }
        if let index = draft.firstIndex(where: { $0.id == gem.id }) { draft[index] = gem }
        else { draft.append(gem) }
        selectedID = gem.id
        return true
    }
    private func nearestPlacement(_ original: PlacedGem, among others: [PlacedGem], mayShrink: Bool) -> PlacedGem? {
        guard let size = layoutSize else { return original }
        if canPlace(original, among: others) { return original }
        let sizes = mayShrink ? [original.size, min(original.size, 24), min(original.size, 16), 8] : [original.size]
        for width in sizes {
            var candidates: [PlacedGem] = []
            for y in stride(from: 12.0, through: Double(size.height) - 12, by: 6) {
                for x in stride(from: 12.0, through: Double(size.width) - 12, by: 6) {
                    var gem = original; gem.size = width; gem.x = x / size.width; gem.y = y / size.height
                    if canPlace(gem, among: others) { candidates.append(gem) }
                }
            }
            if let closest = candidates.min(by: {
                hypot(($0.x-original.x)*size.width, ($0.y-original.y)*size.height) < hypot(($1.x-original.x)*size.width, ($1.y-original.y)*size.height)
            }) { return closest }
        }
        return nil
    }
    func add(_ choice: GemChoice) {
        guard editing else { return }
        let gem = PlacedGem(asset: choice.id, x: 0.5, y: 0.7, size: 28)
        if let safe = nearestPlacement(gem, among: draft, mayShrink: true) { place(safe) }
    }
    func remove(_ id: UUID?) { guard editing, let id else { return }; draft.removeAll { $0.id == id }; if selectedID == id { selectedID = nil } }
    func adjust(_ id: UUID, scale: Double = 1, rotation: Double = 0) {
        guard editing, let index = draft.firstIndex(where: { $0.id == id }) else { return }
        var gem = draft[index]
        gem.size = min(120, max(8, gem.size * scale)); gem.rotation += rotation
        place(gem)
    }
    func updateLayout(stereo: CGRect?, decoration: CGRect? = nil, obstacles: [CGRect]) {
        guard let stereo, stereo.width > 0, stereo.height > 0 else { return }
        let local = obstacles.map { $0.offsetBy(dx: -stereo.minX, dy: -stereo.minY) }
        // List virtualization can briefly omit preference frames; never erase known controls.
        if local.isEmpty, !blocked.isEmpty { return }
        guard layoutSize != stereo.size || blocked != local else { return }
        layoutSize = stereo.size; blocked = local
        if pristine, let decoration {
            let localBand = decoration.offsetBy(dx: -stereo.minX, dy: -stereo.minY)
            for index in saved.indices {
                let offset: Double = index == 1 ? 3 : (index == 2 ? -3 : 0)
                saved[index].y = (localBand.midY + offset) / stereo.height
            }
            draft = saved
        }
        // Existing artwork is moved to the nearest free metal surface after a layout change.
        // Its IDs, shapes and rotations remain intact; persistence happens when Done is chosen.
        func arrange(_ gems: [PlacedGem]) -> [PlacedGem] {
            var result: [PlacedGem] = []
            for gem in gems {
                if let safe = nearestPlacement(gem, among: result, mayShrink: true) { result.append(safe) }
            }
            return result
        }
        if !editing { let safe = arrange(saved); if safe != saved { saved = safe; draft = safe } }
        else { let safe = arrange(draft); if safe != draft { draft = safe } }
    }

}

struct StudioFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct StickerDisplay: View {
    @ObservedObject var studio: StickerStudioStore
    var body: some View {
        GeometryReader { geometry in
            ForEach(studio.visible) { gem in
                gemView(gem, in: geometry.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stereo decorations")
        .accessibilityValue("\(studio.visible.count) stickers")
    }
    private func gemView(_ gem: PlacedGem, in size: CGSize) -> some View {
        let artwork = Image(gem.asset).resizable().scaledToFit().frame(width: gem.size, height: gem.size)
            .overlay {
                if studio.editing && studio.selectedID == gem.id {
                    Rectangle().stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3])).padding(-4)
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black).frame(width: 20, height: 20).background(.white, in: Circle())
                        .offset(x: gem.size / 2 + 8, y: gem.size / 2 + 8).accessibilityHidden(true)
                }
            }
            .rotationEffect(.degrees(gem.rotation))
            .position(x: size.width * gem.x, y: size.height * gem.y)
            .opacity(studio.activeID == gem.id ? 0 : 1)
        let name = gem.asset.replacingOccurrences(of: "Gem_", with: "").replacingOccurrences(of: "_", with: " ")
        let accessible = artwork.accessibilityElement(children: .ignore).accessibilityAddTraits(.isImage).accessibilityLabel("Placed \(name) sticker")
            .accessibilityValue("Size \(Int(gem.size)), rotation \(Int(gem.rotation)) degrees")
            .accessibilityIdentifier("placedGem-\(gem.id.uuidString)")
        return accessible
            .accessibilityAction(named: "Make larger") { studio.adjust(gem.id, scale: 1.1) }
            .accessibilityAction(named: "Make smaller") { studio.adjust(gem.id, scale: 0.9) }
            .accessibilityAction(named: "Rotate") { studio.adjust(gem.id, rotation: 15) }
            .accessibilityAction(named: "Remove") { studio.remove(gem.id) }
    }

}

struct StickerSheet: View {
    @ObservedObject var studio: StickerStudioStore
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("sticker sheet").font(AppType.font(.headline))
                Spacer()
                Button { studio.remove(studio.selectedID) } label: { Image(systemName: "trash").frame(width: 40, height: 40) }
                    .accessibilityLabel("Remove selected sticker").accessibilityIdentifier("stickerTrash")
                    .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["trash": geometry.frame(in: .global)]) })
                Button { studio.finish() } label: { Image(systemName: "checkmark").frame(width: 40, height: 40) }
                    .accessibilityLabel("Done decorating").accessibilityIdentifier("stickerDone")
            }
            .buttonStyle(.plain)
            VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(studio.choices) { choice in
                    Button {
                        studio.add(choice)
                    } label: {
                        Image(choice.id).resizable().scaledToFit().frame(width: 44, height: 44)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.label)
                    .accessibilityIdentifier("stickerSource-\(choice.id)")
                    .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: [choice.id: geometry.frame(in: .global)]) })
                }
                if studio.choices.count < 5 { ForEach(0..<(5 - studio.choices.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 60) } }
            }
            .offset(x: studio.pageSwipe)
            .clipped()
            .id(studio.page)
            .background(GeometryReader { geometry in Color.clear.preference(key: StudioFramesKey.self, value: ["sheet": geometry.frame(in: .global)]) })
            HStack(spacing: 7) {
                ForEach(0..<studio.pageCount, id: \.self) { page in
                    Button { withAnimation(.easeOut(duration: 0.15)) { studio.page = page } } label: {
                        Circle().fill(page == studio.page ? rose : Color.secondary.opacity(0.35)).frame(width: 5, height: 5).frame(width: 12, height: 20)
                    }.buttonStyle(.plain).accessibilityLabel("Sticker page \(page + 1) of \(studio.pageCount)")
                        .accessibilityIdentifier("stickerPage-\(page)")
                }
            }
            }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.025), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .gray.opacity(0.25), .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stickerSheet")
    }
}

struct StickerTouchLayer: UIViewRepresentable {
    @ObservedObject var studio: StickerStudioStore
    let frames: [String: CGRect]
    func makeUIView(context: Context) -> StickerTouchView {
        let view = StickerTouchView(); view.studio = studio; return view
    }
    func updateUIView(_ view: StickerTouchView, context: Context) { view.studio = studio; view.frames = frames; view.isUserInteractionEnabled = studio.editing }
}

@MainActor
final class StickerTouchView: UIView, UIGestureRecognizerDelegate {
    weak var studio: StickerStudioStore?
    var frames: [String: CGRect] = [:]
    private var session: Session?
    private let ghost = UIImageView()
    private var displayLink: CADisplayLink?
    private weak var scrolling: UIScrollView?
    private var pan: UIPanGestureRecognizer!
    private var pinch: UIPinchGestureRecognizer!
    private var rotation: UIRotationGestureRecognizer!

    private struct Session {
        var gem: PlacedGem
        var existing: Bool
        var center: CGPoint
        var origin: CGPoint
        var panBase: CGPoint
        var sizeBase: Double
        var angleBase: Double
        var paging: Bool
        var transformed = false
        var directionChosen = false
        var handleTransform = false
        var handleDistance: CGFloat = 1
        var handleAngle: CGFloat = 0
        var pageDelta: CGFloat = 0
        var lastValid: PlacedGem?
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isMultipleTouchEnabled = true
        isAccessibilityElement = false; accessibilityElementsHidden = true; clipsToBounds = true
        ghost.contentMode = .scaleAspectFit; ghost.isUserInteractionEnabled = false; ghost.isHidden = true; addSubview(ghost)
        pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:))); pan.maximumNumberOfTouches = 2
        pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotated(_:)))
        for gesture in [pan!, pinch!, rotation!] {
            gesture.delegate = self; gesture.cancelsTouchesInView = false; gesture.delaysTouchesBegan = false; addGestureRecognizer(gesture)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate() }

    private func local(_ key: String) -> CGRect? {
        guard let global = frames[key] else { return nil }
        let origin = convert(CGPoint.zero, to: nil)
        return global.offsetBy(dx: -origin.x, dy: -origin.y)
    }
    private func gemRect(_ gem: PlacedGem) -> CGRect {
        guard let stereo = local("stereo") else { return .zero }
        return CGRect(x: stereo.minX + stereo.width * gem.x - gem.size / 2, y: stereo.minY + stereo.height * gem.y - gem.size / 2, width: gem.size, height: gem.size)
    }
    private func handlePoint(_ gem: PlacedGem) -> CGPoint {
        let rect = gemRect(gem)
        let angle = gem.rotation * .pi / 180
        let distance = gem.size / 2 + 8
        return CGPoint(x: rect.midX + distance * (cos(angle) - sin(angle)), y: rect.midY + distance * (sin(angle) + cos(angle)))
    }
    private func isHandle(_ point: CGPoint, gem: PlacedGem) -> Bool {
        let handle = handlePoint(gem)
        return studio?.selectedID == gem.id && hypot(point.x - handle.x, point.y - handle.y) < 23
    }
    private func hitGem(_ point: CGPoint) -> PlacedGem? {
        if let selected = studio?.draft.first(where: { $0.id == studio?.selectedID }), isHandle(point, gem: selected) { return selected }
        return studio?.draft.reversed().first { isHandle(point, gem: $0) || gemRect($0).insetBy(dx: -max(12, (44 - $0.size) / 2), dy: -max(12, (44 - $0.size) / 2)).contains(point) }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard studio?.editing == true, bounds.contains(point) else { return nil }
        if session != nil { return self }
        if local("sheet")?.contains(point) == true { return self }
        // The selected corner handle may extend over a control even though its
        // artwork is clear of it. Keep that handle reachable while decorating.
        if let selected = studio?.draft.first(where: { $0.id == studio?.selectedID }), isHandle(point, gem: selected) { return self }
        if frames.keys.filter({ $0.hasPrefix("protected-") }).contains(where: { local($0)?.contains(point) == true }) { return nil }
        if hitGem(point) != nil { return self }
        return nil
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session == nil, let touch = touches.first, let studio, studio.editing else { return }
        let point = touch.location(in: self)
        if let gem = hitGem(point) {
            let center = CGPoint(x: gemRect(gem).midX, y: gemRect(gem).midY)
            session = Session(gem: gem, existing: true, center: center, origin: point, panBase: center, sizeBase: gem.size, angleBase: gem.rotation, paging: false)
            if isHandle(point, gem: gem) {
                session?.handleTransform = true
                session?.handleDistance = max(1, hypot(point.x - center.x, point.y - center.y))
                session?.handleAngle = atan2(point.y - center.y, point.x - center.x)
            }
            session?.lastValid = gem
            studio.selectedID = gem.id; studio.activeID = gem.id
        } else if let choice = studio.choices.first(where: { local($0.id)?.contains(point) == true }) {
            beginSourceSession(choice, at: point)
        } else if local("sheet")?.contains(point) == true {
            let gem = PlacedGem(asset: "", x: 0.5, y: 0.5, size: 35)
            session = Session(gem: gem, existing: false, center: point, origin: point, panBase: point, sizeBase: 35, angleBase: 0, paging: true)
        }
        guard session != nil else { return }
        scrolling = findScrollView(window)
        displayLink?.invalidate(); displayLink = CADisplayLink(target: self, selector: #selector(autoScroll)); displayLink?.add(to: .main, forMode: .common)
        paint()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remaining = event?.allTouches?.contains(where: { $0.phase != .ended && $0.phase != .cancelled }) ?? false
        if !remaining {
            DispatchQueue.main.async { [weak self] in self?.endActiveGesture() }
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if [pan!, pinch!, rotation!].contains(where: { $0.state == .began || $0.state == .changed }) { return }
        complete(cancelled: true)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pan && otherGestureRecognizer.view is UIScrollView
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard var current = session else { return }
        let finger = gesture.location(in: self)
        let delta = CGPoint(x: finger.x - current.origin.x, y: finger.y - current.origin.y)
        if current.handleTransform {
            let point = gesture.location(in: self)
            let distance = hypot(point.x - current.center.x, point.y - current.center.y)
            current.gem.size = min(120, max(8, current.sizeBase * distance / current.handleDistance))
            current.gem.rotation = current.angleBase + (atan2(point.y - current.center.y, point.x - current.center.x) - current.handleAngle) * 180 / .pi
            session = current; paint()
            if gesture.state == .ended { endActiveGesture() }
            else if gesture.state == .cancelled { complete(cancelled: true) }
            return
        }
        chooseSourceDirection(&current, delta: delta)
        if !current.paging { current.center = CGPoint(x: current.panBase.x + delta.x, y: current.panBase.y + delta.y) }
        else { current.pageDelta = delta.x; current.center = gesture.location(in: self) }
        if current.paging { studio?.pageSwipe = max(-70, min(70, delta.x * 0.35)) }
        session = current; paint()
        if gesture.state == .ended { endActiveGesture() }
        else if gesture.state == .cancelled || gesture.state == .failed { complete(cancelled: true) }
    }
    private func startTransform() {
        guard var current = session, !current.gem.asset.isEmpty else { return }
        current.paging = false; current.directionChosen = true; current.transformed = true; current.panBase = current.center
        current.origin = pan.location(in: self)
        pan.setTranslation(.zero, in: self); session = current
    }
    func beginSourceSession(_ choice: GemChoice, at point: CGPoint) {
        let gem = PlacedGem(asset: choice.id, x: 0.5, y: 0.5, size: 35)
        session = Session(gem: gem, existing: false, center: point, origin: point, panBase: point, sizeBase: 35, angleBase: 0, paging: false)
    }
    func beginPinch() {
        startTransform()
        if var current = session { current.sizeBase = current.gem.size; session = current }
    }
    func scaleActiveGesture(_ scale: CGFloat) {
        guard var current = session, !current.gem.asset.isEmpty else { return }
        current.gem.size = min(120, max(8, current.sizeBase * pow(scale, 1.35))); session = current; paint()
    }
    func beginRotation() {
        startTransform()
        if var current = session { current.angleBase = current.gem.rotation; session = current }
    }
    func rotateActiveGesture(_ angle: CGFloat) {
        guard var current = session, !current.gem.asset.isEmpty else { return }
        current.gem.rotation = current.angleBase + angle * 180 / .pi; session = current; paint()
    }
    private func chooseSourceDirection(_ current: inout Session, delta: CGPoint) {
        guard !current.existing, !current.transformed, !current.directionChosen else { return }
        if abs(delta.x) > 12, abs(delta.x) > abs(delta.y) * 1.1 { current.directionChosen = true; current.paging = true }
        else if abs(delta.y) > 12, abs(delta.y) >= abs(delta.x) * 0.9 { current.directionChosen = true; current.paging = false }
    }
    func moveActiveGesture(to point: CGPoint) {
        guard var current = session else { return }
        let delta = CGPoint(x: point.x - current.origin.x, y: point.y - current.origin.y)
        chooseSourceDirection(&current, delta: delta)
        current.center = point; current.pageDelta = delta.x
        session = current; paint()
    }
    var isDraggingPreviewVisible: Bool { !ghost.isHidden }

    func endActiveGesture() { complete(cancelled: false) }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { beginPinch() }
        scaleActiveGesture(gesture.scale)
    }
    @objc private func rotated(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { beginRotation() }
        rotateActiveGesture(gesture.rotation)
    }
    private func paint() {
        guard var current = session, !current.paging, !current.gem.asset.isEmpty, let studio else { ghost.isHidden = true; return }
        guard current.existing || current.transformed || current.directionChosen else { ghost.isHidden = true; return }
        studio.updateLayout(stereo: frames["stereo"], decoration: frames["decoration"], obstacles: frames.filter { $0.key.hasPrefix("protected-") }.map { $0.value })
        let overTrash = current.existing && local("trash")?.insetBy(dx: -8, dy: -8).contains(current.center) == true
        if let stereo = local("stereo"), !overTrash {
            var proposed = current.gem
            proposed.x = (current.center.x - stereo.minX) / stereo.width
            proposed.y = (current.center.y - stereo.minY) / stereo.height
            // The ghost follows the fingers freely; collision rules apply only on release.
            current.gem = proposed
        }
        session = current
        ghost.isHidden = false; ghost.image = UIImage(named: current.gem.asset)
        ghost.bounds = CGRect(x: 0, y: 0, width: current.gem.size, height: current.gem.size)
        ghost.center = current.center; ghost.transform = CGAffineTransform(rotationAngle: current.gem.rotation * .pi / 180)
        ghost.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor; ghost.layer.borderWidth = 0.5
    }
    private func complete(cancelled: Bool) {
        guard var current = session, let studio else { return }
        defer { session = nil; ghost.isHidden = true; studio.activeID = nil; studio.pageSwipe = 0; displayLink?.invalidate(); displayLink = nil }
        guard !cancelled else { return }
        studio.updateLayout(stereo: frames["stereo"], decoration: frames["decoration"], obstacles: frames.filter { $0.key.hasPrefix("protected-") }.map { $0.value })
        if current.paging {
            let delta = current.pageDelta
            if abs(delta) > 25 { withAnimation(.easeOut(duration: 0.15)) { studio.changePage(delta < 0 ? 1 : -1) } }
            return
        }
        if current.existing, local("trash")?.insetBy(dx: -8, dy: -8).contains(current.center) == true {
            studio.remove(current.gem.id); UIImpactFeedbackGenerator(style: .light).impactOccurred(); return
        }
        guard let stereo = local("stereo"), stereo.contains(current.center) else { return }
        current.gem.x = (current.center.x - stereo.minX) / stereo.width
        current.gem.y = (current.center.y - stereo.minY) / stereo.height
        studio.place(current.gem) // Invalid drops leave an existing sticker in its original place.
    }
    private func findScrollView(_ view: UIView?) -> UIScrollView? {
        guard let view else { return nil }
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled, scroll.contentSize.height > scroll.bounds.height + 20 { return scroll }
        for child in view.subviews { if let match = findScrollView(child) { return match } }
        return nil
    }
    @objc private func autoScroll() {
        guard let current = session, !current.paging, let scroll = scrolling,
              current.existing || current.transformed || current.directionChosen else { return }
        let speed: CGFloat = current.center.y < 55 ? -4 : (current.center.y > bounds.height - 55 ? 4 : 0)
        guard speed != 0 else { return }
        let minY = -scroll.adjustedContentInset.top
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(maxY, max(minY, scroll.contentOffset.y + speed))), animated: false)
    }
}
