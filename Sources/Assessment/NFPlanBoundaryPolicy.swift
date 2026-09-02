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
        let adjusted = calendar.date(byAdding: .hour, value: -hour, to: date) ?? date
        let logicalDay = calendar.dateComponents([.era, .year, .month, .day], from: adjusted)
        var startComponents = logicalDay
        startComponents.hour = hour
        startComponents.minute = 0
        startComponents.second = 0
        let boundaryStart = calendar.date(from: startComponents)
            ?? calendar.startOfDay(for: adjusted).addingTimeInterval(Double(hour) * 3_600)
        let nextBoundary = calendar.date(byAdding: .day, value: 1, to: boundaryStart)
            ?? boundaryStart.addingTimeInterval(86_400)
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
