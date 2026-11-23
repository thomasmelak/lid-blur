import XCTest
@testable import LidBlurCore

final class LidBlurCoreTests: XCTestCase {
    func testTriggerFirstReading() {
        var open = LidTrigger(openAngle: 40)
        XCTAssertEqual(open.update(angle: 110), true)
        var closed = LidTrigger(openAngle: 40)
        XCTAssertEqual(closed.update(angle: 5), false)
    }

    func testTriggerFiresOncePerTransition() {
        var trigger = LidTrigger(openAngle: 40, hysteresis: 10)
        XCTAssertEqual(trigger.update(angle: 0), false)
        XCTAssertNil(trigger.update(angle: 20))
        XCTAssertNil(trigger.update(angle: 39))
        XCTAssertEqual(trigger.update(angle: 40), true)
        XCTAssertNil(trigger.update(angle: 120))
        // Inside the hysteresis band: still open.
        XCTAssertNil(trigger.update(angle: 35))
        XCTAssertEqual(trigger.update(angle: 30), false)
        XCTAssertNil(trigger.update(angle: 35))
        XCTAssertEqual(trigger.update(angle: 45), true)
    }

    func testTriggerReset() {
        var trigger = LidTrigger()
        _ = trigger.update(angle: 100)
        trigger.reset()
        XCTAssertNil(trigger.isOpen)
        XCTAssertEqual(trigger.update(angle: 100), true)
    }

    func testApproachConverges() {
        var value = 1.0
        for _ in 0..<120 { value = Easing.approach(value, 0, dt: 1.0 / 60, timeConstant: 0.07) }
        XCTAssertEqual(value, 0)
    }

    func testEasings() {
        for f in [Easing.easeOutCubic, Easing.easeInOutCubic, Easing.smoothstep] {
            XCTAssertEqual(f(0), 0, accuracy: 1e-9)
            XCTAssertEqual(f(1), 1, accuracy: 1e-9)
        }
    }

    func testUnfoldMask() {
        XCTAssertTrue(UnfoldMask(strength: 1).isFullyBlurred)
        XCTAssertEqual(UnfoldMask(strength: 1).bottomCoverage, 1)
        XCTAssertTrue(UnfoldMask(strength: 0).isFullyClear)
        let half = UnfoldMask(strength: 0.5)
        XCTAssertGreaterThan(half.clearEdge, 0)
        XCTAssertLessThan(half.blurEdge, 1)
        XCTAssertEqual(half.blurEdge - half.clearEdge, UnfoldMask.feather, accuracy: 1e-9)
    }

    func testFoldLook() {
        XCTAssertEqual(FoldLook(fold: 0), FoldLook(fold: -1))
        XCTAssertEqual(FoldLook(fold: 0).blur, 0)
        XCTAssertEqual(FoldLook(fold: 0).dim, 0)
        XCTAssertEqual(FoldLook(fold: 1).blur, 1)
        XCTAssertEqual(FoldLook(fold: 1).dim, 1)
        // Blur leads, darkness follows.
        let early = FoldLook(fold: 0.3)
        XCTAssertGreaterThan(early.blur, 0.9)
        XCTAssertEqual(early.dim, 0)
        let late = FoldLook(fold: 0.8)
        XCTAssertEqual(late.blur, 1)
        XCTAssertGreaterThan(late.dim, 0.5)
        XCTAssertLessThan(late.dim, 1)
    }
}
