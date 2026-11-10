import XCTest

/// A reply's code blocks, inline code and quotes as Telegram draws them (#2984): a code block's Copy takes the whole
/// block, a tap on inline code takes the span, and a long quote folds and opens. What was copied is read back by
/// pasting it into the composer (the runner may not read the app's pasteboard).
///   PORT=18950 MOCK_REPLY_BLOCKS=1 python3 scripts/mock/mock_hub.py &
///   TEST_RUNNER_PERSONA_MOCK_HUB=http://127.0.0.1:18950 xcodebuild test … -only-testing:PersonaUITests/ReplyBlocksTests
final class ReplyBlocksTests: XCTestCase {
    private var app: XCUIApplication!

    private var composer: XCUIElement { app.descendants(matching: .any)["shell-composer-field"].firstMatch }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let hub = ProcessInfo.processInfo.environment["PERSONA_MOCK_HUB"] else {
            throw XCTSkip("needs scripts/mock/mock_hub.py with MOCK_REPLY_BLOCKS=1 (PERSONA_MOCK_HUB)")
        }
        app = XCUIApplication()
        let pair = "persona://pair?url=" + hub.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "&token=mock"
        app.launchArguments = ["-pairURL", pair, "-tab", "dev", "-openSession", "macbook/a1f3c2d4-0000-4000-8000-0000005e1ec9",
                               "-openChatsFresh", "YES"]
        MainActor.assumeIsolated {
            app.launchPinned()
            let last = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "有问题再找我")).firstMatch
            XCTAssertTrue(last.waitForExistence(timeout: 20), "the reply did not show:\n\(app.debugDescription)")
            acceptIconAlert(timeout: 2)
        }
    }

    private func menuItem(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "(elementType == %d OR elementType == %d) AND label == %@",
            XCUIElement.ElementType.menuItem.rawValue, XCUIElement.ElementType.button.rawValue, label)).firstMatch
    }

    @MainActor private func toast(_ words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// What the app put on the pasteboard, pasted into the composer from its edit menu (a paste the user taps asks
    /// nothing), then deleted again so no draft is left.
    @MainActor private func pasted() -> String {
        let field = composer
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no composer:\n\(app.debugDescription)")
        field.tap()
        field.press(forDuration: 1.0)
        let paste = menuItem("粘贴")
        XCTAssertTrue(paste.waitForExistence(timeout: 3), "no 粘贴 in the composer's edit menu:\n\(app.debugDescription)")
        paste.tap()
        sleep(1)
        let got = composer.value as? String ?? ""
        composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: got.count + 4))
        return got
    }

    @MainActor func testACodeBlocksCopyTakesTheWholeBlock() throws {
        let copy = app.buttons.matching(identifier: "code-block-copy").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "no Copy on the code block:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["ts"].exists, "the fence's language is not in the block's bar")
        XCTAssertEqual(app.buttons.matching(identifier: "code-block-copy").count, 2, "the fence without a language has no Copy")
        copy.tap()
        XCTAssertTrue(toast("已拷贝代码").waitForExistence(timeout: 3), "no Code copied notice")
        XCTAssertEqual(pasted(), "export async function clear(page: string) {\n  await caches.delete(`page:${page}`)\n  return reload(page)\n}")
    }

    @MainActor func testATapOnInlineCodeCopiesIt() throws {
        let code = app.links.matching(NSPredicate(format: "label CONTAINS %@", "npm run build")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5), "inline code is not tappable:\n\(app.debugDescription)")
        code.tap()
        XCTAssertTrue(toast("已拷贝").waitForExistence(timeout: 3), "no Copied notice")
        XCTAssertEqual(pasted(), "npm run build")
    }

    @MainActor func testALongQuoteFoldsAndOpens() throws {
        let quotes = app.descendants(matching: .any).matching(identifier: "reply-quote")
        XCTAssertTrue(quotes.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(quotes.count, 2)
        let open = app.buttons["展开"].firstMatch
        XCTAssertTrue(open.exists, "the long quote is not folded")
        let folded = quotes.element(boundBy: 1).frame.height
        open.tap()
        let fold = app.buttons["收起"].firstMatch
        XCTAssertTrue(fold.waitForExistence(timeout: 3), "no 收起 on the opened quote")
        XCTAssertGreaterThan(quotes.element(boundBy: 1).frame.height, folded + 20, "opened, the quote did not grow")
        fold.tap()
        XCTAssertTrue(app.buttons["展开"].firstMatch.waitForExistence(timeout: 3), "folded again, no 展开")
    }
}
