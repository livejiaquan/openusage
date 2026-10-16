import Foundation

/// The short pace phrase beside a meter's name, in Tokamak's wording: "on pace" while the window is
/// on course to finish with room to spare, "empty in ~1h 9m" (a warning) when the current pace runs
/// out before the reset, the "~3% spare" cushion when it is close, and "Limit reached" once spent.
struct PaceLabel: Equatable {
    let text: String
    /// Drawn in the notice color; the bar below still carries the severity color.
    let isWarning: Bool
}

extension WidgetData {
    func paceLabel(for state: MeterState, now: Date = Date()) -> PaceLabel? {
        switch state {
        case .spent:
            return PaceLabel(text: "Limit reached", isWarning: true)
        case .runningOut:
            guard let seconds = secondsToRunOut(now: now), let duration = Formatters.compactDuration(seconds) else {
                return PaceLabel(text: "runs out before reset", isWarning: true)
            }
            return PaceLabel(text: "empty in ~\(duration)", isWarning: true)
        case .closeToLimit(let spare, _):
            return PaceLabel(text: spare, isWarning: false)
        case .healthy:
            return alwaysShowPacing ? PaceLabel(text: "on pace", isWarning: false) : nil
        case .noData, .level:
            return nil
        }
    }
}
