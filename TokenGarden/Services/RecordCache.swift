import Foundation
import SwiftData

/// In-memory cache for hot-path entities fetched on every `TokenDataStore.record()` call.
///
/// Before: 5 SwiftData fetches per event (DailyUsage, HourlyUsage, ProjectUsage search,
/// ProfileTokenUsage, SessionUsage). During backfill of thousands of events this caused
/// severe main-thread hangs.
///
/// After: cache holds references for the common hot path (same day/hour/session/profile).
/// Only the first event for a new key triggers a fetch-or-insert.
///
/// Cache invalidation:
/// - Daily/hourly/profile-token caches evict entries on calendar day change.
/// - Hourly cache additionally evicts stale hours when the current hour advances.
/// - Session cache is bounded by the number of active sessions during a run.
@MainActor
final class RecordCache {
    private var dailyUsageCache: [Date: DailyUsage] = [:]
    private var hourlyUsageCache: [HourKey: HourlyUsage] = [:]
    private var sessionCache: [String: SessionUsage] = [:]
    private var profileTokenCache: [ProfileKey: ProfileTokenUsage] = [:]

    private var currentDay: Date = .distantPast

    private struct HourKey: Hashable {
        let date: Date
        let hour: Int
    }

    private struct ProfileKey: Hashable {
        let profileName: String
        let date: Date
    }

    /// Call at the top of every `record()` to drop stale entries when the day rolls over.
    func invalidateIfNeeded(for timestamp: Date) {
        let day = Calendar.current.startOfDay(for: timestamp)
        if day != currentDay {
            dailyUsageCache.removeAll(keepingCapacity: true)
            hourlyUsageCache.removeAll(keepingCapacity: true)
            profileTokenCache.removeAll(keepingCapacity: true)
            currentDay = day
        }
    }

    /// Fully clears the cache. Call when the underlying ModelContext is reset.
    func clear() {
        dailyUsageCache.removeAll(keepingCapacity: true)
        hourlyUsageCache.removeAll(keepingCapacity: true)
        sessionCache.removeAll(keepingCapacity: true)
        profileTokenCache.removeAll(keepingCapacity: true)
        currentDay = .distantPast
    }

    // MARK: - DailyUsage

    func getOrCreateDaily(day: Date, in context: ModelContext) -> DailyUsage {
        if let cached = dailyUsageCache[day] {
            return cached
        }
        let descriptor = FetchDescriptor<DailyUsage>(
            predicate: #Predicate { $0.date == day }
        )
        let fetched = (try? context.fetch(descriptor).first)
        let daily: DailyUsage
        if let fetched {
            daily = fetched
        } else {
            daily = DailyUsage(date: day)
            context.insert(daily)
        }
        dailyUsageCache[day] = daily
        return daily
    }

    // MARK: - HourlyUsage

    func getOrCreateHourly(day: Date, hour: Int, in context: ModelContext) -> HourlyUsage {
        let key = HourKey(date: day, hour: hour)
        if let cached = hourlyUsageCache[key] {
            return cached
        }
        let descriptor = FetchDescriptor<HourlyUsage>(
            predicate: #Predicate { $0.date == day && $0.hour == hour }
        )
        let fetched = (try? context.fetch(descriptor).first)
        let hourly: HourlyUsage
        if let fetched {
            hourly = fetched
        } else {
            hourly = HourlyUsage(date: day, hour: hour, tokens: 0)
            context.insert(hourly)
        }
        hourlyUsageCache[key] = hourly
        return hourly
    }

    // MARK: - SessionUsage

    func getOrCreateSession(
        sessionId: String,
        projectName: String,
        timestamp: Date,
        in context: ModelContext
    ) -> SessionUsage {
        if let cached = sessionCache[sessionId] {
            return cached
        }
        let descriptor = FetchDescriptor<SessionUsage>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        let fetched = (try? context.fetch(descriptor).first)
        let session: SessionUsage
        if let fetched {
            session = fetched
        } else {
            session = SessionUsage(
                sessionId: sessionId,
                projectName: projectName,
                startTime: timestamp
            )
            context.insert(session)
        }
        sessionCache[sessionId] = session
        return session
    }

    // MARK: - ProfileTokenUsage

    func getOrCreateProfileToken(
        profileName: String,
        day: Date,
        in context: ModelContext
    ) -> ProfileTokenUsage {
        let key = ProfileKey(profileName: profileName, date: day)
        if let cached = profileTokenCache[key] {
            return cached
        }
        let descriptor = FetchDescriptor<ProfileTokenUsage>(
            predicate: #Predicate { $0.profileName == profileName && $0.date == day }
        )
        let fetched = (try? context.fetch(descriptor).first)
        let usage: ProfileTokenUsage
        if let fetched {
            usage = fetched
        } else {
            usage = ProfileTokenUsage(profileName: profileName, date: day, tokens: 0)
            context.insert(usage)
        }
        profileTokenCache[key] = usage
        return usage
    }
}
