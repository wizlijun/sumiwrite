import XCTest

/// 替 `scripts/sim-rime.sh` 在模拟器上点按:脚本用 simkey 发实体键盘按键、用 simctl 截图,
/// 点按候选行(候选、‹ ›、状态字和它弹出的菜单项)要靠 XCUITest。两边经同步目录里的文件说话(该目录由脚本经环境变量
/// `TEST_RUNNER_SIM_RIME_SYNC` 传入,模拟器里的测试进程能直接读写宿主的路径):
///
/// - 本测试接上应用后写 `ready`;
/// - 脚本写 `cmd`(先写临时文件再改名),一行:`tap <无障碍标签>`、`menu <无障碍标签>` 或 `quit`;
///   `menu` 点状态字直到弹出菜单:状态字淡出后点第一下只让它显出来(ios.md §3.6),这时再点一下;
/// - 本测试删掉 `cmd`,执行,写 `done`:`ok` 或 `missing <标签>`。
///
/// 不经脚本直接跑时跳过。
final class TapServer: XCTestCase {
    func testServe() throws {
        guard let path = ProcessInfo.processInfo.environment["SIM_RIME_SYNC"] else {
            throw XCTSkip("只由 apps/ios/scripts/sim-rime.sh 运行")
        }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        let cmd = dir.appendingPathComponent("cmd"), done = dir.appendingPathComponent("done")
        let app = XCUIApplication()
        app.activate()
        try "ok".write(to: dir.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(1200)
        while Date() < deadline {
            guard let line = try? String(contentsOf: cmd, encoding: .utf8) else {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            try? FileManager.default.removeItem(at: cmd)
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text == "quit" {
                try "ok".write(to: done, atomically: true, encoding: .utf8)
                return
            }
            var reply = "unknown \(text)"
            if text.hasPrefix("tap ") || text.hasPrefix("menu ") {
                let label = String(text.drop { $0 != " " }.dropFirst())
                let button = app.buttons[label].firstMatch
                if button.waitForExistence(timeout: 30), button.isHittable {
                    button.tap()
                    if text.hasPrefix("menu "), !app.buttons["中文"].waitForExistence(timeout: 1.5) {
                        button.tap()
                    }
                    reply = "ok"
                } else {
                    reply = "missing \(label)"
                }
            }
            try reply.write(to: done, atomically: true, encoding: .utf8)
        }
        XCTFail("超时:脚本没有发 quit")
    }
}
