import Foundation

runTimelineTests()
runEventLogTests()
runDecodingTests()
runAFKTests()
runProjectSearchTests()
runTimeMoveTests()

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
