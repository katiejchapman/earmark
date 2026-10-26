import SwiftUI

struct StickerSheetIcon: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            var sheet = Path()
            sheet.move(to: CGPoint(x: 4, y: 2))
            sheet.addLine(to: CGPoint(x: 20, y: 2))
            sheet.addQuadCurve(to: CGPoint(x: 22, y: 4), control: CGPoint(x: 22, y: 2))
            sheet.addLine(to: CGPoint(x: 22, y: 14))
            sheet.addQuadCurve(to: CGPoint(x: 14, y: 22), control: CGPoint(x: 20, y: 21))
            sheet.addLine(to: CGPoint(x: 4, y: 22))
            sheet.addQuadCurve(to: CGPoint(x: 2, y: 20), control: CGPoint(x: 2, y: 22))
            sheet.addLine(to: CGPoint(x: 2, y: 4))
            sheet.addQuadCurve(to: CGPoint(x: 4, y: 2), control: CGPoint(x: 2, y: 2))
            sheet.move(to: CGPoint(x: 14, y: 22))
            sheet.addQuadCurve(to: CGPoint(x: 22, y: 14), control: CGPoint(x: 13, y: 13))
            context.stroke(sheet, with: .foreground, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
            var heart = Path()
            heart.move(to: CGPoint(x: 7, y: 11)); heart.addCurve(to: CGPoint(x: 4.5, y: 7), control1: CGPoint(x: 3, y: 8.5), control2: CGPoint(x: 4, y: 5.5))
            heart.addQuadCurve(to: CGPoint(x: 7, y: 7), control: CGPoint(x: 6, y: 5)); heart.addQuadCurve(to: CGPoint(x: 9.5, y: 7), control: CGPoint(x: 8, y: 5))
            heart.addQuadCurve(to: CGPoint(x: 7, y: 11), control: CGPoint(x: 11, y: 8.5))
            context.fill(heart, with: .color(Color(red: 0.87, green: 0.64, blue: 0.75)))
            var star = Path(); star.move(to: CGPoint(x: 16, y: 5)); star.addLines([CGPoint(x: 17, y: 7), CGPoint(x: 19, y: 7.5), CGPoint(x: 17.5, y: 9), CGPoint(x: 18, y: 11), CGPoint(x: 16, y: 10), CGPoint(x: 14, y: 11), CGPoint(x: 14.5, y: 9), CGPoint(x: 13, y: 7.5), CGPoint(x: 15, y: 7)]); star.closeSubpath()
            context.stroke(star, with: .foreground, lineWidth: 0.9)
            var diamond = Path(); diamond.move(to: CGPoint(x: 7, y: 14)); diamond.addLines([CGPoint(x: 10, y: 17), CGPoint(x: 7, y: 20), CGPoint(x: 4, y: 17)]); diamond.closeSubpath()
            context.stroke(diamond, with: .foreground, lineWidth: 1)
        }.accessibilityHidden(true)
    }
}
