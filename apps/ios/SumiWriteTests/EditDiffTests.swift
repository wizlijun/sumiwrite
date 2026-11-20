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

    /// 不给光标时先求前缀:重复字符段里的插入落在最右端(只用于没有光标的场合)。
    func test_repeatedCharsWithoutCaretUseLongestPrefix() {
        XCTAssertEqual(EditDiff.between("aaa", "aaaa"), edit(3, 0, "a"))
    }

    // MARK: 锚在光标上(重复字符)

    /// `a|aa` 处再打 `a`:差异落在光标左侧,不跳到这一段的末尾。
    func test_repeatedCharsFollowCaret() {
        XCTAssertEqual(EditDiff.between("aaa", "aaaa", caret: 2), edit(1, 0, "a"))
        XCTAssertEqual(EditDiff.between("aaa", "aaaa", caret: 0), edit(0, 0, "a"))
        XCTAssertEqual(EditDiff.between("aaa", "aaaa", caret: 4), edit(3, 0, "a"))
    }

    /// `a|` 后接空行与下一段(`a\n\nb`),按回车。
    func test_enterBeforeBlankLineFollowsCaret() {
        XCTAssertEqual(EditDiff.between("a\n\nb", "a\n\n\nb", caret: 2), edit(1, 0, "\n"))
    }

    /// `谢|谢` 处再打 `谢`;以及 `谢|` 后打 `谢`。
    func test_doubledCharacterFollowsCaret() {
        XCTAssertEqual(EditDiff.between("谢谢", "谢谢谢", caret: 2), edit(1, 0, "谢"))
        XCTAssertEqual(EditDiff.between("谢", "谢谢", caret: 2), edit(1, 0, "谢"))
    }

    /// `a\n\n|\nb` 处退格。
    func test_backspaceInsideBlankLinesFollowsCaret() {
        XCTAssertEqual(EditDiff.between("a\n\n\nb", "a\n\nb", caret: 2), edit(2, 1, ""))
    }

    /// `谢谢|谢` 处退格。
    func test_backspaceOnDoubledCharacterFollowsCaret() {
        XCTAssertEqual(EditDiff.between("谢谢谢", "谢谢", caret: 1), edit(1, 1, ""))
    }

    /// emoji 旁的重复字符,以及重复的 emoji;UTF-16 偏移按代理对计。
    func test_emojiNextToRepeatedCharacterFollowsCaret() {
        XCTAssertEqual(EditDiff.between("😀aa", "😀aaa", caret: 4), edit(3, 0, "a"))
        XCTAssertEqual(EditDiff.between("😀😀", "😀😀😀", caret: 4), edit(2, 0, "😀"))
        XCTAssertEqual(EditDiff.between("😀😀😀", "😀😀", caret: 2), edit(2, 2, ""))
    }

    /// 光标落在字素中间、超出文本,或在改动左侧时,仍给出正确的差异。
    func test_inconsistentCaretStillGivesValidEdit() {
        XCTAssertEqual(EditDiff.between("a😀b", "a😀😀b", caret: 4), edit(3, 0, "😀"))
        XCTAssertEqual(EditDiff.between("ab", "abc", caret: 99), edit(2, 0, "c"))
        XCTAssertEqual(EditDiff.between("abc", "abcd", caret: 0), edit(3, 0, "d"))
        XCTAssertEqual(EditDiff.between("abc", "abxc", caret: -5), edit(2, 0, "x"))
    }
}
