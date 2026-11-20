import XCTest
@testable import SumiWrite

final class EditDiffTests: XCTestCase {
    private func edit(_ l: Int, _ n: Int, _ r: String) -> TextEdit {
        TextEdit(range: NSRange(location: l, length: n), replacement: r)
    }

    func test_identicalIsNil() { XCTAssertNil(EditDiff.between("abc", "abc")) }
    func test_appendAscii() { XCTAssertEqual(EditDiff.between("ab", "abc"), edit(2, 0, "c")) }
    func test_chineseCommit() { XCTAssertEqual(EditDiff.between("你", "你好"), edit(1, 0, "好")) }
    func test_emojiInsertMiddle() { XCTAssertEqual(EditDiff.between("a😀b", "a😀😀b"), edit(3, 0, "😀")) }
    func test_zwjFamilyDeleted() { XCTAssertEqual(EditDiff.between("x👨‍👩‍👧y", "xy"), edit(1, 8, "")) }
    func test_combiningAccentAdded() { XCTAssertEqual(EditDiff.between("e", "e\u{301}"), edit(0, 1, "e\u{301}")) }
    func test_repeatedCharsPreferSuffixSafe() { XCTAssertEqual(EditDiff.between("aaa", "aaaa"), edit(3, 0, "a")) }
}
