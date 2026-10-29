import SwiftUI

// iOS 15 backport: ToolbarItemPlacement.topBarLeading / .topBarTrailing are
// iOS 16+. Keep the official placement on iOS 16+ and use the equivalent
// navigation-bar placement on iOS 15.
enum NanoMuseToolbarPlacement {
    static var leading: ToolbarItemPlacement {
        if #available(iOS 16.0, *) {
            return .topBarLeading
        } else {
            return .navigationBarLeading
        }
    }

    static var trailing: ToolbarItemPlacement {
        if #available(iOS 16.0, *) {
            return .topBarTrailing
        } else {
            return .navigationBarTrailing
        }
    }
}
