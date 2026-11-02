import Testing
import UIKit
@testable import EldiaShift

@Suite("画面の明るさ（自動・ライト・ダーク）")
@MainActor
struct AppearanceTests {
    @Test("自動は端末の設定に合わせ、ライト・ダークはその明るさにする")
    func styles() {
        #expect(AppearanceMode.allCases.map(\.title) == ["自動", "ライト", "ダーク"])
        #expect(AppearanceMode.system.style == .unspecified)
        #expect(AppearanceMode.light.style == .light)
        #expect(AppearanceMode.dark.style == .dark)
    }

    @Test("保存する名前は変えない（前の版で選んだ明るさを読めるように）")
    func savedNames() {
        #expect(AppearanceMode(rawValue: "system") == .system)
        #expect(AppearanceMode(rawValue: "light") == .light)
        #expect(AppearanceMode(rawValue: "dark") == .dark)
        #expect(AppearanceMode.key == "appearanceMode")
    }
}
