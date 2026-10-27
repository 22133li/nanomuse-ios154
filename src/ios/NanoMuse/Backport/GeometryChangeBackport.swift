import SwiftUI

// iOS 15 backport: `onGeometryChange(for:action:)` is iOS 17+.

private struct GeometryChangeKey<T: Equatable>: PreferenceKey {
    static var defaultValue: T? { nil }
    static func reduce(value: inout T?, nextValue: () -> T?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Keeps the official `onGeometryChange` semantics on iOS 17+, and uses a
    /// preference-backed measurement on iOS 15/16. The transform receives the
    /// same GeometryProxy the official API gives its closure.
    @ViewBuilder
    func onGeometryChangeBackport<T: Equatable>(
        for type: T.Type,
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
            self.background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GeometryChangeKey<T>.self,
                        value: transform(proxy)
                    )
                }
            )
            .onPreferenceChange(GeometryChangeKey<T>.self) { newValue in
                if let newValue { action(newValue) }
            }
        }
    }
}
