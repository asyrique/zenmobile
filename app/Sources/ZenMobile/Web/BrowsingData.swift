import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Clears what sites leave behind: cookies and site data (storage,
/// databases, service workers, permissions), and cached files. History is
/// Places' (`Places.clearHistory`).
@MainActor enum BrowsingData {
    static func clear(siteData: Bool, cache: Bool) async {
        guard siteData || cache else { return }
        #if os(Android)
        GeckoBrowsingData.clear(siteData: siteData, cache: cache)
        #elseif canImport(WebKit)
        var types: Set<String> = []
        if siteData {
            types.formUnion([
                WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage,
                WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeWebSQLDatabases,
                WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFileSystem,
            ])
        }
        if cache {
            types.formUnion([
                WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache,
            ])
        }
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
        #endif
    }
}

#if SKIP
import org.mozilla.geckoview.StorageController

// Kotlin side (transpiled by Skip). Public so Kotlin doesn't rename it on
// the JVM, where Skip's bridge looks it up.
struct GeckoBrowsingData {
    public static func clear(siteData: Bool, cache: Bool) {
        var flags: Int64 = 0
        if siteData {
            flags = flags | StorageController.ClearFlags.SITE_DATA | StorageController.ClearFlags.AUTH_SESSIONS
        }
        if cache {
            flags = flags | StorageController.ClearFlags.ALL_CACHES
        }
        let runtime = ZenGeckoRuntime.get(ProcessInfo.processInfo.androidContext)
        runtime.storageController.clearData(flags)
    }
}
#endif
