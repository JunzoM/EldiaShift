# シフト表（iPad / iPhone）

チームのシフトを作って共有するアプリ。データは端末内に保存し、iCloud で同期する（サーバーなし）。

## 段階

1. **データの形・取り込み・月表示（見るだけ）** ← いまここ
2. 編集（月表示のマス・日ごとのタイムライン、ドラッグで移動・伸縮、30分刻み）
3. iCloud 共有（複数の管理者で共同編集）・変更履歴
4. 公開（月間・週間の PDF / 画像、前回の公開からの変更点の文章、LINE・メールで共有）
5. 管理者向けの通知、仕上げ、App Store 申請

## PC版からの移行

PC版シフト表の「設定」→「💾 データ管理」→「バックアップを保存」で作った `.json` を、
このアプリの「バックアップを取り込む」で読み込む。このアプリで書き出した `.json` は PC版でも読み込める。

## 開発

- Xcode で `EldiaShift.xcodeproj` を開く（ファイルはフォルダに置くだけで自動でプロジェクトに入る）
- 対応 OS：iOS / iPadOS 17 以降
- iCloud コンテナ：`iCloud.com.bestdelight.eldiashift`（Signing & Capabilities で登録）
- GitHub Actions でビルド・テスト（Swift Testing）を確認する
