import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The share sheet, from code (ShareLink covers buttons).
@MainActor enum Share {
    static func text(_ text: String) {
        #if os(Android)
        AndroidSharing.share(text: text)
        #endif
    }
}

@MainActor enum Clipboard {
    static func copy(_ text: String) {
        #if os(Android)
        AndroidClipboard.copy(text: text)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
