import XCTest
@testable import LidBlurCore

final class LidBlurCoreTests: XCTestCase {
    func testCurveEndpoints() {
        let curve = BlurCurve(closedAngle: 10, clearAngle: 70)
        XCTAssertEqual(curve.strength(forAngle: 0), 1)
        XCTAssertEqual(curve.strength(forAngle: 10), 1)
        XCTAssertEqual(curve.strength(forAngle: 70), 0)
        XCTAssertEqual(curve.strength(forAngle: 120), 0)
        XCTAssertEqual(curve.strength(forAngle: 40), 0.5, accuracy: 1e-9)
    }

    func testCurveMonotonicallyDecreasing() {
        let curve = BlurCurve()
        var previous = 2.0
        for angle in stride(from: 0.0, through: 180.0, by: 1.0) {
            let s = curve.strength(forAngle: angle)
            XCTAssertLessThanOrEqual(s, previous)
            previous = s
        }
    }

    func testFollowerEasesInsteadOfSnapping() {
        // Lid flung open: target drops from 1 to 0 instantly.
        var follower = EasedFollower(value: 1)
        follower.step(towards: 0, dt: 1.0 / 60)
        XCTAssertGreaterThan(follower.value, 0.99, "starts gently")
        var previous = follower.value
        var time = 1.0 / 60
        while follower.value > 0, time < 3 {
            follower.step(towards: 0, dt: 1.0 / 60)
            XCTAssertLessThanOrEqual(follower.value, previous, "never overshoots back")
            XCTAssertGreaterThanOrEqual(follower.value, 0, "never overshoots past")
            previous = follower.value
            time += 1.0 / 60
        }
        XCTAssertEqual(follower.value, 0)
        XCTAssertTrue(follower.isSettled)
        XCTAssertGreaterThan(time, 0.6)
        XCTAssertLessThan(time, 1.3)
    }

    func testFollowerTracksSlowMovement() {
        var follower = EasedFollower(value: 1)
        var target = 1.0
        for _ in 0..<180 { // 3 s slow open
            target = max(0, target - 1.0 / 180)
            follower.step(towards: target, dt: 1.0 / 60)
            XCTAssertLessThan(abs(follower.value - target), 0.1)
        }
    }

    func testFollowerStepSizeIndependent() {
        var coarse = EasedFollower(value: 1)
        var fine = EasedFollower(value: 1)
        coarse.step(towards: 0, dt: 0.2)
        for _ in 0..<20 { fine.step(towards: 0, dt: 0.01) }
        XCTAssertEqual(coarse.value, fine.value, accuracy: 1e-9)
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

    func testBlurProfileNeverSharpWhileFolded() {
        let open = BlurProfile(fold: 0)
        XCTAssertEqual(open.topRadius, 0)
        XCTAssertFalse(open.isVisible)

        let closed = BlurProfile(fold: 1)
        XCTAssertEqual(closed.topRadius, BlurProfile.maxRadius)
        XCTAssertEqual(closed.hingeRatio, 1)

        var previous = Double.infinity
        for step in stride(from: 1.0, to: 0.0, by: -0.05) {
            let p = BlurProfile(fold: step)
            XCTAssertGreaterThan(p.hingeRadius, 0, "hinge must stay blurred at fold \(step)")
            XCTAssertGreaterThanOrEqual(p.hingeRatio, BlurProfile.hingeFloor)
            XCTAssertLessThanOrEqual(p.hingeRadius, p.topRadius)
            XCTAssertLessThanOrEqual(p.topRadius, previous + 1e-9, "radius eases down as the lid opens")
            previous = p.topRadius
        }
    }

    func testBlurProfileUniform() {
        XCTAssertEqual(BlurProfile(fold: 0.3, gradient: false).hingeRatio, 1)
        XCTAssertEqual(BlurProfile(fold: 1, scale: 0.5).topRadius, BlurProfile.maxRadius / 2, accuracy: 1e-9)
    }

    func testCoverageGradient() {
        XCTAssertEqual(BlurProfile.coverage(atDepth: 0, hingeRatio: 0.4), 1)
        XCTAssertEqual(BlurProfile.coverage(atDepth: 1, hingeRatio: 0.4), 0.4, accuracy: 1e-9)
        XCTAssertEqual(BlurProfile.coverage(atDepth: 0.7, hingeRatio: 1), 1)
        XCTAssertLessThan(BlurProfile.coverage(atDepth: 0.6, hingeRatio: 0.4),
                          BlurProfile.coverage(atDepth: 0.4, hingeRatio: 0.4))
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
