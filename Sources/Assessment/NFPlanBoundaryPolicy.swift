import Foundation

struct NFPlanBoundaryContext: Equatable, Sendable {
    let evaluatedAt: Date
    let timeZoneIdentifier: String
    let utcOffsetSeconds: Int
    let dayBoundaryHour: Int
    let boundaryStart: Date
    let nextBoundary: Date

    static func make(
        at date: Date,
        dayBoundaryHour: Int,
        calendar suppliedCalendar: Calendar = .current
    ) -> NFPlanBoundaryContext {
        let calendar = suppliedCalendar
        let hour = min(12, max(0, dayBoundaryHour))
        let today = calendar.startOfDay(for: date)
        // Resolve the requested wall-clock hour separately on each civil day.
        // Subtracting elapsed hours misclassifies the hour after a DST jump;
        // adding a day to an adjusted missing hour can also shift tomorrow.
        // A missing boundary occurs at the next valid time; a repeated boundary
        // uses its first occurrence, so there is one learner-day transition.
        func boundary(on day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
                ?? calendar.startOfDay(for: day)
        }
        let todayBoundary = boundary(on: today)
        let boundaryStart: Date
        let nextBoundary: Date
        if date < todayBoundary {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: today)
                ?? today.addingTimeInterval(-86_400)
            boundaryStart = boundary(on: previousDay)
            nextBoundary = todayBoundary
        } else {
            boundaryStart = todayBoundary
            let followingDay = calendar.date(byAdding: .day, value: 1, to: today)
                ?? today.addingTimeInterval(86_400)
            nextBoundary = boundary(on: followingDay)
        }
        return NFPlanBoundaryContext(
            evaluatedAt: date,
            timeZoneIdentifier: calendar.timeZone.identifier,
            utcOffsetSeconds: calendar.timeZone.secondsFromGMT(for: date),
            dayBoundaryHour: hour,
            boundaryStart: boundaryStart,
            nextBoundary: nextBoundary
        )
    }
}

enum NFPlanTravelPolicy {
    static let maximumPreservationInterval: TimeInterval = 18 * 3_600

    static func contextChanged(
        storedTimeZoneIdentifier: String,
        storedUTCOffsetSeconds: Int,
        newContext: NFPlanBoundaryContext
    ) -> Bool {
        storedTimeZoneIdentifier != newContext.timeZoneIdentifier
            || storedUTCOffsetSeconds != newContext.utcOffsetSeconds
    }

    static func canPreserve(
        planCreatedAt: Date,
        at date: Date,
        storedTimeZoneIdentifier: String,
        storedUTCOffsetSeconds: Int,
        newContext: NFPlanBoundaryContext
    ) -> Bool {
        let elapsed = date.timeIntervalSince(planCreatedAt)
        return elapsed >= 0
            && elapsed <= maximumPreservationInterval
            && contextChanged(
                storedTimeZoneIdentifier: storedTimeZoneIdentifier,
                storedUTCOffsetSeconds: storedUTCOffsetSeconds,
                newContext: newContext
            )
    }

    static func preservationDeadline(
        planCreatedAt: Date,
        newContext: NFPlanBoundaryContext
    ) -> Date {
        min(
            planCreatedAt.addingTimeInterval(maximumPreservationInterval),
            newContext.nextBoundary
        )
    }
}
