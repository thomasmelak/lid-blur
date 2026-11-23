import XCTest
@testable import LidBlurCore

final class BlurCurveTests: XCTestCase {
    func testEndpoints() {
        let curve = BlurCurve(closedAngle: 10, clearAngle: 70)
        XCTAssertEqual(curve.strength(forAngle: 0), 1)
        XCTAssertEqual(curve.strength(forAngle: 10), 1)
        XCTAssertEqual(curve.strength(forAngle: 70), 0)
        XCTAssertEqual(curve.strength(forAngle: 120), 0)
        XCTAssertEqual(curve.strength(forAngle: 40), 0.5, accuracy: 1e-9)
    }

    func testMonotonicallyDecreasing() {
        let curve = BlurCurve()
        var previous = 2.0
        for angle in stride(from: 0.0, through: 180.0, by: 1.0) {
            let s = curve.strength(forAngle: angle)
            XCTAssertLessThanOrEqual(s, previous)
            previous = s
        }
    }

    func testDegenerateCurve() {
        let curve = BlurCurve(closedAngle: 50, clearAngle: 50)
        XCTAssertEqual(curve.strength(forAngle: 49), 1)
        XCTAssertEqual(curve.strength(forAngle: 51), 0)
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
