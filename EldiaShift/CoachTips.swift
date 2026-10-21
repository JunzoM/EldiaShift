import SwiftUI
import TipKit

// MARK: - コーチマーク（操作のヒント）
// くどくならないよう、次の決まりにしている。
// ・その機能を初めて押したときだけ出す（押していない機能のヒントは出さない）
// ・1つのヒントは1回だけ（閉じるか、説明した操作をしたら二度と出ない）
// ・ふだんから見えている説明文は置かず、ヒントに任せる
// 設定の「操作のヒントをもう一度見る」で、次に開いたときから最初の状態に戻せる。

enum CoachTips {
    private static let resetKey = "resetTipsOnNextLaunch"

    /// アプリの起動時に1回呼ぶ
    static func configure() {
        if ProcessInfo.processInfo.arguments.contains("-demoTips") {
            // 画面確認用：ヒントの見た目を撮る
            try? Tips.resetDatastore()
            Tips.showAllTipsForTesting()
        } else if DemoMode.enabled || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // 画面確認・テストでは出さない（スクリーンショットを毎回同じにするため）
            Tips.hideAllTipsForTesting()
        }
        if UserDefaults.standard.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetKey)
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    /// 次に開いたときから、ヒントを最初の状態に戻す（TipKit は起動中に戻せないため）
    static func resetOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: resetKey)
    }

    /// 押したことを記録する（そのヒントが出るきっかけ）
    static func tapped(_ event: Tips.Event<Tips.EmptyDonation>) {
        Task { await event.donate() }
    }
}

/// 鉛筆（編集する）を初めて押したとき
struct EditModeTip: Tip {
    static let tapped = Tips.Event(id: "tappedEdit")

    var title: Text { Text("編集できるようになりました") }
    var message: Text? { Text("マスを押すと勤務を選べます。日の表示ではバーをドラッグして変えられます。終わったら、ここをもう一度押すとロックに戻ります。") }
    var image: Image? { Image(systemName: "pencil") }
    var rules: [Rule] { #Rule(Self.tapped) { $0.donations.count >= 1 } }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 編集中にマスを初めて押したとき（選択画面の上に出す）
struct CellPickerTip: Tip {
    var title: Text { Text("押すとすぐ決まります") }
    var message: Text? { Text("ひな形を押すと、この日のシフトになります。ひな形にない時刻は下の「この日だけ時刻を直接入力」で。上の検索で絞り込めます。") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 日のタイムラインを初めて開いて、編集中のとき
struct TimelineTip: Tip {
    var title: Text { Text("ドラッグで変えられます") }
    var message: Text? { Text("バーを左右に動かすと時刻が、両端を動かすと長さが変わります（30分刻み）。空いているところを押すと、その時刻から8時間のシフトを作ります。") }
    var image: Image? { Image(systemName: "hand.draw") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}


/// 集計を初めて開いたとき
struct SummaryTip: Tip {
    var title: Text { Text("時間は休憩を引いた実働です") }
    var message: Text? { Text("引く休憩は 設定 →「休憩の決まり」で変えられます。有休の残りは、入社日と週間パターンから出しています。") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}

/// 印刷・PDF を初めて開いたとき
struct PrintTip: Tip {
    var title: Text { Text("PDFはLINEやメールで送れます") }
    var message: Text? { Text("「PDFを共有」から LINE・メール・AirDrop・ファイルに保存ができます。白黒で印刷しても土日や有休が見分けられます。") }
    var image: Image? { Image(systemName: "square.and.arrow.up") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}
