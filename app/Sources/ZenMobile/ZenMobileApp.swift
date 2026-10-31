import Foundation
import SkipFuse
import SwiftUI
import ZenCore

/// A logger for the ZenMobile module.
let logger: Logger = Logger(subsystem: "io.github.asyrique.zenmobile", category: "ZenMobile")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
/* SKIP @bridge */public struct ZenMobileRootView : View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        RootContent()
    }
}

/// Holds the app-wide models; kept out of the bridged root view so the
/// Kotlin side never sees them.
struct RootContent: View {
    @Environment(\.scenePhase) var scenePhase
    @State var app = AppModel(dataDirectory: RootContent.dataDirectory(), deviceName: "Zen Mobile")
    @State var downloads: Downloads
    @State var places: Places
    @State var browser: BrowserModel

    @MainActor init() {
        let downloads = Downloads(directory: Downloads.defaultDirectory())
        let places = Places(path: RootContent.dataDirectory().appendingPathComponent("places.db").path)
        _downloads = State(initialValue: downloads)
        _places = State(initialValue: places)
        _browser = State(initialValue: BrowserModel(
            storeURL: RootContent.dataDirectory().appendingPathComponent("open-tabs.json"),
            downloads: downloads,
            places: places))
    }

    var body: some View {
        NavigationStack {
            BrowserView()
        }
        .environment(app)
        .environment(browser)
        .environment(downloads)
        .environment(places)
        .preferredColorScheme(.dark)
        .task {
            await TrackerBlocking.apply()
            // Tabs other devices send here open in the background.
            app.onTabsReceived = { [browser] tabs in browser.receive(tabs) }
            app.onTabsClosed = { [browser] urls in browser.closeTabs(at: urls) }
            await app.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await app.didBecomeActive() }
            }
        }
    }

    static func dataDirectory() -> URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("zen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class ZenMobileAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = ZenMobileAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
