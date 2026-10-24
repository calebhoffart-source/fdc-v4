import Foundation

// Pure, easily testable rules with no Screen Time entitlement dependency.
enum AccountabilityRules {
    static func nextDayRepTarget(recreationalMinutes: Int) -> Int { max(0, min(1440, recreationalMinutes)) }
    static func maxSafeTrainingAssignment(target: Int) -> Int { min(max(0, target), 50) }
    static func travelLoanRepayment(borrowedMinutes: Int) -> Int { Int(ceil(Double(max(0, borrowedMinutes)) / 10.0)) }
    static func remainingPhysicalReps(logged: Int) -> Int { max(0, 50 - max(0, logged)) }
}
