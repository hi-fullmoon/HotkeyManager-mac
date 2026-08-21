import Carbon
import XCTest
@testable import HotkeyManager

final class KeyCodeMapTests: XCTestCase {
    func testParsesSupportedAliasesAndCanonicalDisplay() {
        let combo = KeyCodeMap.parse(" control + option + A ")

        XCTAssertEqual(combo?.keyCode, 0)
        XCTAssertEqual(combo?.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(combo?.display, "⌃⌥A")
    }

    func testRejectsUnknownModifierInsteadOfCreatingBareHotkey() {
        XCTAssertNil(KeyCodeMap.parse("cmdd+1"))
        XCTAssertNil(KeyCodeMap.parse("cmd+wat+1"))
    }

    func testRejectsEmptySegments() {
        XCTAssertNil(KeyCodeMap.parse("cmd++1"))
        XCTAssertNil(KeyCodeMap.parse("+cmd+1"))
        XCTAssertNil(KeyCodeMap.parse("cmd+1+"))
    }

    func testRejectsBareTypingKeysButAllowsFunctionKeys() {
        XCTAssertNil(KeyCodeMap.parse("a"))
        XCTAssertNil(KeyCodeMap.parse("1"))
        XCTAssertNotNil(KeyCodeMap.parse("f12"))
    }

    func testRecorderConversionUsesSameSafetyPolicy() {
        XCTAssertNil(KeyCodeMap.comboString(keyCode: 0, modifiers: 0))
        XCTAssertEqual(
            KeyCodeMap.comboString(keyCode: 0, modifiers: UInt32(cmdKey)),
            "cmd+a"
        )
    }
}
