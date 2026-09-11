import Foundation

struct ConfirmedCalendarSelection: Equatable {
    var calendarIDs: Set<String>
    var confirmedSourceIDs: Set<String>

    init(
        calendarIDs: Set<String> = [],
        confirmedSourceIDs: Set<String> = []
    ) {
        self.calendarIDs = calendarIDs
        self.confirmedSourceIDs = confirmedSourceIDs
    }

    mutating func setSource(
        _ sourceID: String,
        confirmedAsGoogle: Bool,
        calendarIDs sourceCalendarIDs: Set<String>
    ) {
        if confirmedAsGoogle {
            confirmedSourceIDs.insert(sourceID)
        } else {
            confirmedSourceIDs.remove(sourceID)
            calendarIDs.subtract(sourceCalendarIDs)
        }
    }

    mutating func setCalendar(
        _ calendarID: String,
        enabled: Bool,
        sourceID: String
    ) {
        guard confirmedSourceIDs.contains(sourceID) else { return }
        if enabled {
            calendarIDs.insert(calendarID)
        } else {
            calendarIDs.remove(calendarID)
        }
    }
}
