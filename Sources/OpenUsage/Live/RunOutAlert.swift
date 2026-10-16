import Foundation

/// "Claude · Session runs out about 22m before it resets at this pace." Shown in the Activity card
/// only while some enabled limit is projected to run out before its reset.
struct RunOutAlert: Equatable {
    let providerName: String
    let metricTitle: String
    let leadTime: TimeInterval

    var message: String {
        "\(metricTitle) runs out about \(Formatters.compactDuration(leadTime) ?? "1m") before it resets at this pace."
    }

    /// The candidate that runs out soonest wins; healthy or unprojectable meters never alert.
    static func soonest(_ candidates: [(providerName: String, data: WidgetData)], now: Date) -> RunOutAlert? {
        candidates
            .compactMap { candidate -> (alert: RunOutAlert, runOut: TimeInterval)? in
                guard let runOut = candidate.data.secondsToRunOut(now: now),
                      let lead = candidate.data.runOutLeadTime(now: now)
                else { return nil }
                return (RunOutAlert(providerName: candidate.providerName, metricTitle: candidate.data.title,
                                    leadTime: lead), runOut)
            }
            .min { $0.runOut < $1.runOut }?
            .alert
    }
}
