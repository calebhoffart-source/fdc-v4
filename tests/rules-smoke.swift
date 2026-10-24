import Foundation

@main
struct Check {
    static func main() {
        assert(AccountabilityRules.nextDayRepTarget(recreationalMinutes: 135) == 135)
        assert(AccountabilityRules.nextDayRepTarget(recreationalMinutes: -2) == 0)
        assert(AccountabilityRules.nextDayRepTarget(recreationalMinutes: 1800) == 1440)
        assert(AccountabilityRules.maxSafeTrainingAssignment(target: 135) == 50)
        assert(AccountabilityRules.maxSafeTrainingAssignment(target: 23) == 23)
        assert(AccountabilityRules.travelLoanRepayment(borrowedMinutes: 31) == 4)
        assert(AccountabilityRules.travelLoanRepayment(borrowedMinutes: 10) == 1)
        assert(AccountabilityRules.remainingPhysicalReps(logged: 47) == 3)
        assert(AccountabilityRules.remainingPhysicalReps(logged: 100) == 0)
        print("9 accountability rule checks passed")
    }
}
