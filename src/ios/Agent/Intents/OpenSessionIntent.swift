import AppIntents
import Foundation

/// Opens a specific chat session in the Minis app.
@available(iOS 16, *)
struct OpenSessionIntent: AppIntent {
    static var title: Foundation.LocalizedStringResource = "Open Session"
    static var description = IntentDescription("Opens a nanoMuse chat session in the app.")
    static var openAppWhenRun = true

    @Parameter(title: "Session")
    var session: SessionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .openSessionFromIntent,
            object: nil,
            userInfo: ["sessionId": session.id]
        )
        return .result()
    }
}

extension Notification.Name {
    // Ungated: this is a plain notification name with no iOS 16 dependency;
    // it was previously inside an @available(iOS 16, *) extension, which made
    // every posting/observing site iOS 16-only for no reason.
    static let openSessionFromIntent = Notification.Name("openSessionFromIntent")
}
