import SwiftUI

// iOS 15 backport: `onGeometryChange(for:action:)` is iOS 17+.
//
// iOS 15/16 path notes (round15):
// - (T1-2) The preference key is parameterized by a per-call-site tag, so a
//   measurement can only ever reach its own call site's action. Previously
//   every call site measuring the same value type shared one key, and values
//   from nested producers merged into the wrong consumer (e.g. the composer
//   twin's height overwrote the composer column's height, which positions
//   the floating scroll buttons).
// - (T1-0) The action is never invoked synchronously from the preference
//   change: preference delivery happens inside the layout pass, and writing
//   caller state there re-drives layout in the same pass — the
//   ViewGraphGeometryObservers.needsUpdate SIGTRAP upstream documents at
//   its own onGeometryChange call sites. Delivery is deferred to the next
//   main-runloop turn and de-duplicated per call site, matching the
//   official API's out-of-band delivery.

/// Per-call-site tags for `onGeometryChangeBackport`. Each measurement point
/// gets its own tag so its preference channel stays private on iOS 15/16;
/// the tags are unused on iOS 17+.
enum GeometryChangeShellHeaderTag {}
enum GeometryChangeComposerColumnTag {}
enum GeometryChangeFloatingBarTag {}
enum GeometryChangeComposerFrameTag {}
enum GeometryChangeTopSafeAreaTag {}
enum GeometryChangeComposerTwinTag {}
enum GeometryChangeMessageRowTag {}

private struct GeometryChangeKey<Tag, T: Equatable>: PreferenceKey {
    static var defaultValue: T? { nil }
    static func reduce(value: inout T?, nextValue: () -> T?) {
        if let next = nextValue() { value = next }
    }
}

/// Reference box holding the last delivered value for one call site.
/// Mutating it does not invalidate any view, so the de-duplication
/// bookkeeping itself can never re-drive layout.
private final class GeometryChangeLastValue<T: Equatable> {
    var value: T?
}

private struct GeometryChangeBackportModifier<Tag, T: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> T
    let action: (T) -> Void
    @State private var lastValue = GeometryChangeLastValue<T>()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GeometryChangeKey<Tag, T>.self,
                        value: transform(proxy)
                    )
                }
            )
            .onPreferenceChange(GeometryChangeKey<Tag, T>.self) { newValue in
                guard let newValue, newValue != lastValue.value else { return }
                lastValue.value = newValue
                let action = self.action
                DispatchQueue.main.async {
                    action(newValue)
                }
            }
    }
}

extension View {
    /// Keeps the official `onGeometryChange` semantics on iOS 17+, and uses a
    /// preference-backed measurement on iOS 15/16. The transform receives the
    /// same GeometryProxy the official API gives its closure.
    @ViewBuilder
    func onGeometryChangeBackport<Tag, T: Equatable>(
        for type: T.Type,
        tag: Tag.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onGeometryChange(for: T.self) { proxy in
                transform(proxy)
            } action: { value in
                action(value)
            }
        } else {
            self.modifier(GeometryChangeBackportModifier<Tag, T>(transform: transform, action: action))
        }
    }
}
