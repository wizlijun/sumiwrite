import XCTest
@testable import SumiWrite

final class DeskPostureTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
    private let fold = CGRect(x: 0, y: 340, width: 1000, height: 20)

    func test_partiallyOpenWithHorizontalDivision() {
        XCTAssertEqual(DeskPosture.foldTop(hinge: .partiallyOpen, divisions: [fold], bounds: bounds), 340)
    }

    func test_fullyOpenOrClosedIsNil() {
        for hinge in [HingeState.fullyOpen, .closed, .unknown, nil] {
            XCTAssertNil(DeskPosture.foldTop(hinge: hinge, divisions: [fold], bounds: bounds))
        }
    }

    func test_verticalDivisionIsIgnored() {
        let vertical = CGRect(x: 490, y: 0, width: 20, height: 700)
        XCTAssertNil(DeskPosture.foldTop(hinge: .partiallyOpen, divisions: [vertical], bounds: bounds))
    }

    func test_noDivisionIsNil() {
        XCTAssertNil(DeskPosture.foldTop(hinge: .partiallyOpen, divisions: [], bounds: bounds))
    }

    func test_divisionOutsideBoundsIsIgnored() {
        for r in [CGRect(x: 0, y: 700, width: 1000, height: 20),
                  CGRect(x: 0, y: -20, width: 1000, height: 20),
                  CGRect(x: 0, y: 340, width: 1000, height: 0),
                  CGRect(x: 1200, y: 340, width: 1000, height: 20)] {
            XCTAssertNil(DeskPosture.foldTop(hinge: .partiallyOpen, divisions: [r], bounds: bounds))
        }
    }
}
