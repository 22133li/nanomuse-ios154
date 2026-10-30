import SwiftUI

// iOS 15 backport: AnyShape is iOS 16+. Simple type-erased Shape.
struct BackportAnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        self.pathBuilder = { rect in shape.path(in: rect) }
    }
    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// iOS 15 backport: UnevenRoundedRectangle is iOS 16+.
struct BackportUnevenRoundedRectangle: Shape {
    var topLeadingRadius: CGFloat = 0
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0
    var topTrailingRadius: CGFloat = 0
    /// Kept for source compatibility with the official initialisers. The
    /// multi-radius path is drawn with circular arcs on iOS 15; on iOS 16+
    /// the system type is used directly and this value is never consulted.
    var style: RoundedCornerStyle = .continuous

    init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0,
         bottomTrailingRadius: CGFloat = 0, topTrailingRadius: CGFloat = 0,
         style: RoundedCornerStyle = .continuous) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
        self.style = style
    }

    func path(in rect: CGRect) -> Path {
        // iOS 16+ draws the official shape unchanged, so the new systems keep
        // the exact corner geometry (continuous style included).
        if #available(iOS 16.0, *) {
            return UnevenRoundedRectangle(
                topLeadingRadius: topLeadingRadius,
                bottomLeadingRadius: bottomLeadingRadius,
                bottomTrailingRadius: bottomTrailingRadius,
                topTrailingRadius: topTrailingRadius,
                style: style
            ).path(in: rect)
        }
        let half = min(rect.width, rect.height) / 2
        let tl = min(max(0, topLeadingRadius), half)
        let bl = min(max(0, bottomLeadingRadius), half)
        let br = min(max(0, bottomTrailingRadius), half)
        let tr = min(max(0, topTrailingRadius), half)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        path.closeSubpath()
        return path
    }
}
