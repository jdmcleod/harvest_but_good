import Foundation

runTimelineTests()
runEventLogTests()
runDecodingTests()
runAFKTests()
runProjectSearchTests()
runTimeMoveTests()
await runAppStateTests()

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
