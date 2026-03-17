//
//  SharedDataManager.swift
//  MBox Explorer
//
//  Manages data sharing between main app and widget via App Group
//
//  Author: Jordan Koch
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Manages shared data between the main app and widget extension
class SharedDataManager {

    /// App Group identifier for data sharing
    static let appGroupIdentifier = "group.com.jkoch.mboxexplorer"

    /// Key for storing widget data in UserDefaults
    private static let widgetDataKey = "MBoxExplorerWidgetData"

    /// Shared instance
    static let shared = SharedDataManager()

    /// UserDefaults container for App Group
    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: SharedDataManager.appGroupIdentifier)
    }

    // MARK: - Widget Data

    /// Saves widget data to the shared container
    func saveWidgetData(_ data: WidgetData) {
        guard let defaults = defaults else {
            print("[SharedDataManager] Error: Unable to access App Group container")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: SharedDataManager.widgetDataKey)
            defaults.synchronize()

            // Notify widget to refresh
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif

            print("[SharedDataManager] Widget data saved successfully")
        } catch {
            print("[SharedDataManager] Error encoding widget data: \(error)")
        }
    }

    /// Loads widget data from the shared container
    func loadWidgetData() -> WidgetData {
        guard let defaults = defaults else {
            print("[SharedDataManager] Error: Unable to access App Group container")
            return .empty
        }

        guard let data = defaults.data(forKey: SharedDataManager.widgetDataKey) else {
            print("[SharedDataManager] No widget data found")
            return .empty
        }

        do {
            let decoded = try JSONDecoder().decode(WidgetData.self, from: data)
            return decoded
        } catch {
            print("[SharedDataManager] Error decoding widget data: \(error)")
            return .empty
        }
    }

    /// Clears widget data from the shared container
    func clearWidgetData() {
        guard let defaults = defaults else { return }
        defaults.removeObject(forKey: SharedDataManager.widgetDataKey)
        defaults.synchronize()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - Recent Queries

    private let recentQueriesKey = "MBoxExplorerRecentQueries"
    private let maxRecentQueries = 10

    /// Adds a query to recent queries list
    func addRecentQuery(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        var queries = loadRecentQueries()

        // Remove existing if present
        queries.removeAll { $0.query.lowercased() == query.lowercased() }

        // Add to beginning
        queries.insert(QueryInfo(query: query, timestamp: Date()), at: 0)

        // Limit size
        if queries.count > maxRecentQueries {
            queries = Array(queries.prefix(maxRecentQueries))
        }

        saveRecentQueries(queries)

        // Update widget data with new queries
        updateWidgetQueries(queries)
    }

    /// Loads recent queries from shared container
    func loadRecentQueries() -> [QueryInfo] {
        guard let defaults = defaults,
              let data = defaults.data(forKey: recentQueriesKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([QueryInfo].self, from: data)
        } catch {
            return []
        }
    }

    /// Saves recent queries to shared container
    private func saveRecentQueries(_ queries: [QueryInfo]) {
        guard let defaults = defaults else { return }

        do {
            let encoded = try JSONEncoder().encode(queries)
            defaults.set(encoded, forKey: recentQueriesKey)
            defaults.synchronize()
        } catch {
            print("[SharedDataManager] Error saving recent queries: \(error)")
        }
    }

    /// Updates widget data with recent queries
    private func updateWidgetQueries(_ queries: [QueryInfo]) {
        var currentData = loadWidgetData()
        currentData = WidgetData(
            totalEmails: currentData.totalEmails,
            totalThreads: currentData.totalThreads,
            dateRange: currentData.dateRange,
            topSenders: currentData.topSenders,
            recentQueries: queries,
            lastUpdated: Date(),
            loadedFileName: currentData.loadedFileName
        )
        saveWidgetData(currentData)
    }

    /// Clears recent queries
    func clearRecentQueries() {
        guard let defaults = defaults else { return }
        defaults.removeObject(forKey: recentQueriesKey)
        defaults.synchronize()
        updateWidgetQueries([])
    }
}

// MARK: - Main App Integration Extension

extension SharedDataManager {

    /// Updates widget data from MboxViewModel stats
    /// Call this from the main app when emails are loaded or stats change
    func updateFromStats(
        totalEmails: Int,
        totalThreads: Int,
        dateRange: String,
        topSenders: [(String, Int)],
        loadedFileName: String?
    ) {
        let senderInfos = topSenders.prefix(5).map { name, count in
            // Extract email from name if it contains angle brackets
            let components = name.components(separatedBy: "<")
            let displayName = components.first?.trimmingCharacters(in: .whitespaces) ?? name
            let email: String
            if components.count > 1 {
                email = components[1].replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces)
            } else {
                email = name
            }
            return WidgetSenderInfo(name: displayName, email: email, count: count)
        }

        let currentQueries = loadRecentQueries()

        let widgetData = WidgetData(
            totalEmails: totalEmails,
            totalThreads: totalThreads,
            dateRange: dateRange,
            topSenders: senderInfos,
            recentQueries: currentQueries,
            lastUpdated: Date(),
            loadedFileName: loadedFileName
        )

        saveWidgetData(widgetData)
    }
}
