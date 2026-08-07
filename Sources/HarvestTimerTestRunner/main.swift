import Foundation

runTimelineTests()
runEventLogTests()
runEventLogFormatTests()
runFormattingTests()
runDayTests()
runWeekCalendarTests()
runDecodingTests()
runAFKTests()
runProjectSearchTests()
runTimeMoveTests()
await runAppStateTests()
await runFavoritesTests()

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
