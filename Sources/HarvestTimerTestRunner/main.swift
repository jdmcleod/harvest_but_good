import Foundation

runTimelineTests()
runEventLogTests()
runFormattingTests()
runDayTests()
runWeekCalendarTests()
runDecodingTests()
runAFKTests()
runProjectSearchTests()
runTimeMoveTests()
await runAppStateTests()

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
