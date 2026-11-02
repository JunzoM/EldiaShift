import SwiftUI
import UIKit

// MARK: - 画面の明るさ（自動・ライト・ダーク）

/// 画面の明るさ。端末ごとに覚える（iCloud で同期しない。iPad は明るく、iPhone は暗く、のように分けられる）
enum AppearanceMode: String, CaseIterable, Identifiable {
    /// 端末の設定（コントロールセンターなど）に合わせる
    case system
    case light
    case dark

    static let key = "appearanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "自動"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// アプリのすべての窓に当てる。窓ごと変えるので、シート・共有の画面・確認の画面も同じ明るさになり、
    /// 「自動」に戻したときもすぐ端末の設定に戻る（SwiftUI の preferredColorScheme は自動に戻すと残ることがある）
    @MainActor
    static func apply(_ mode: AppearanceMode) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != mode.style {
                window.overrideUserInterfaceStyle = mode.style
            }
        }
    }
}

/// いちばん外側の画面に付ける：開いたとき・選び直したとき・窓が増えたとき（Mac・iPad の複数の窓）に明るさを当てる
struct AppearanceApplier: ViewModifier {
    @AppStorage(AppearanceMode.key) private var mode: AppearanceMode = .system

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppearanceMode.apply(mode)
                // 画面が窓に入る前に呼ばれることがあるので、入ったあとにもう一度当てる
                Task { @MainActor in AppearanceMode.apply(mode) }
            }
            .onChange(of: mode) { AppearanceMode.apply(mode) }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)) { _ in
                AppearanceMode.apply(mode)
            }
    }
}

/// 設定の「画面の明るさ」
struct AppearancePicker: View {
    @AppStorage(AppearanceMode.key) private var mode: AppearanceMode = .system

    var body: some View {
        Picker(selection: $mode) {
            ForEach(AppearanceMode.allCases) { m in
                // 切り替え（セグメント）は文字か絵のどちらかしか出せないので、文字にする
                Text(m.title).tag(m)
            }
        } label: {
            Label("画面の明るさ", systemImage: "circle.lefthalf.filled")
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("画面の明るさ")
    }
}
