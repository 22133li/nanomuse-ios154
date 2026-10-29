import SwiftUI

// iOS 26 glass entry points are isolated here so older SDK deployment targets
// do not type-check the newer symbols. The call-site availability branches
// preserve the upstream surface and tint choices exactly.
@available(iOS 26.0, *)
struct NanoMuseRegularGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: shape)
    }
}

@available(iOS 26.0, *)
struct NanoMuseTintedGlassSurface: ViewModifier {
    let tint: Color?
    func body(content: Content) -> some View {
        content.glassEffect(tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: .circle)
    }
}

extension View {
    @ViewBuilder
    func nanoMuseRegularGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(NanoMuseRegularGlassSurface(shape: shape))
        } else {
            self
        }
    }

    @ViewBuilder
    func nanoMuseTintedGlass(_ tint: Color?) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(NanoMuseTintedGlassSurface(tint: tint))
        } else {
            self
        }
    }
}

@available(iOS 26.0, *)
private struct NanoMuseGlassMorphIDModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        content.glassEffectID(id, in: namespace)
    }
}

extension View {
    @ViewBuilder
    func nanoMuseGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(NanoMuseGlassMorphIDModifier(id: id, namespace: namespace))
        } else {
            self
        }
    }
}
