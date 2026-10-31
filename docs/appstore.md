# App Store 提出メモ（SHIFT）

## App Store Connect に入れる内容

| 項目 | 内容 |
|---|---|
| 名前 | SHIFT - ホテル・店舗のシフト表 |
| ホーム画面の名前 | SHIFT（アプリの中のロゴ「〇〇 SHIFT」の〇〇は店舗ごとに変更可） |
| サブタイトル | 作って、共有するシフト管理 |
| バンドルID | com.bestdelight.eldiashift |
| SKU | shift-ios |
| 主なカテゴリ | ビジネス（副：仕事効率化） |
| 価格 | 無料 |
| 年齢制限 | 4+（すべての質問「なし」） |
| プライバシーポリシー URL | https://facility-manager-phi.vercel.app/hotel-shift/privacy |
| サポート URL | https://facility-manager-phi.vercel.app/hotel-shift/support |
| マーケティング URL | https://best-delight.com |
| App のプライバシー | 「データを収集しない」 |
| 著作権 | 2026 Junzo Murai |

### プロモーション用テキスト（170文字以内）
iPad・iPhone でシフト表を作って、そのままスタッフに共有。複数店舗・掛け持ち、QRコードからの希望休の申請、人件費の概算にも対応。サーバー不要、データは端末と iCloud にだけ保存します。

### 説明
SHIFT は、ホテルや店舗の現場で使うシフト表アプリです。紙や表計算ソフトで作っていたシフト表を、iPad・iPhone でかんたんに作成・共有できます。

■ シフト表
・月・週・日の3つの表示。日ごとのタイムラインは、ドラッグで移動・伸び縮み（30分刻み）
・早番・遅番・夜勤・公休などを色付きのチップで表示
・週間パターン・期間限定パターンで、毎週のシフトを自動で入力
・まとめて選んで一度に入力、元に戻す・やり直し
・パターンを保存する前に、表が変わる日数を確認

■ 人手不足と労務のチェック
・部門ごと・時間帯ごとの必要人数（適正人員）を決めると、足りない日・時間が赤く表示
・足りない時間に入れられるスタッフを、候補として表示
・連勤・勤務の間隔・週の労働時間・希望休との重なり・年5日の有休を注意

■ 希望休の申請
・事務所に貼る QR コードを、スタッフがスマホで読み取って申請（スタッフはアプリ不要・Android も可）
・届いたリンクを押すだけで取り込み、承認・却下。結果の返事の文章も自動で作成
・申請の内容はサーバーを通らず、LINE などで直接やり取り

■ 人件費
・「〇月〇日から時給〇円（月給〇円）」の履歴で、日ごとの時給を計算
・時間外（1日・週40時間）・深夜の割増を含めた月の概算。部門ごと・一人ずつ、CSV 出力
・端末ごとに人件費・給与を隠す設定（Face ID・パスコードで表示）

■ 複数店舗・掛け持ち
・ホームの会社の下に各店舗が並び、店舗ごとの出勤人数と承認待ちがひと目で分かる
・店舗を切り替えて、店舗ごとのシフト表を管理
・掛け持ちのスタッフは、ほかの店舗で勤務する日もひと目で分かり、二重に入れることを防止

■ 共有・出力
・PDF・印刷（AirPrint）・CSV で出力
・一人ずつのシフト画像を作って LINE で送れる
・前回の公開からの変更点を、文章にして一緒に送れる

■ ホーム
・会社名・ロゴ・写真の見出しの下に、各店舗の今日の様子
・今日の出勤、人手不足の日、未公開の変更、労務の注意をひと目で確認

■ スタッフ
・顔写真・雇用形態の登録。保存せずに閉じるときは確認
・削除の前に、一緒に消えるシフトの日数を表示（退職にする選択も）

■ 安心のデータ管理
・サーバー不要。データは端末と、あなたの iCloud にだけ保存（運営者は受け取りません）
・iCloud 同期で、同じ Apple ID の iPad・iPhone・Mac で同じシフト表を使用
・iCloud 共有で、ほかの管理者とシフト表を共同編集（給与は共有しません）
・バックアップの作成と、自動バックアップからの復元
・会社の色を選んで、アプリ全体の色をそろえられます
・アプリの中のロゴ「〇〇 SHIFT」を、店舗ごとに自分の名前に

### このバージョンの新機能（1.2）
・Mac 版：iPad と同じ画面で Mac でも使えます（追加の購入は不要）。表示メニューから拡大・縮小
・iCloud 共有：ほかの管理者とシフト表を共同編集。見るだけの共有も（給与は共有しません）
・シフト編集：マスごとのメモ、15分刻み、希望休の日に入れるときの確認
・人件費：月の予算と使用率、前月比、部門の割合、年間の推移、シフト明細の CSV
・希望休の申請：まとめて承認・却下、部門で絞り込み、代理で登録、宛名ごとの返事
・印刷：A3、1か月を1つの表に、人数が多いときは次のページへ、メモの一覧、全ページのプレビュー
・スタッフ：都道府県の最低賃金の表示（毎年の改定も自動で反映）、似顔絵、10円単位の切り上げ
・ホーム：人件費・承認待ちのカード、月の出勤人数のカレンダー、店舗の切り替え
・iPad・Mac：スタッフ・希望休を左右2列で表示、画面全体のデザインを見直し
・シフト表のマスが「文字の大きさ」の設定に合わせて大きくなります

### このバージョンの新機能（1.1）
・希望休の申請：事務所に貼るQRコードから、スタッフがスマホで申請。届いたリンクを押すだけで取り込み、承認・却下・返事まで
・人件費：時給・月給の履歴、時間外・週40時間・深夜の割増を含めた月の概算。端末ごとに隠す設定も
・ホーム：会社の下に各店舗が並び、店舗ごとの出勤人数と承認待ちがひと目で分かる
・スタッフの顔写真・雇用形態、編集画面の閉じる前の確認
・パターンを保存する前に、表が変わる日数を表示

### キーワード（100文字以内・カンマ区切り）
シフト,シフト表,シフト管理,勤務表,ホテル,旅館,飲食店,店舗,スタッフ,アルバイト,パート,希望休,人件費,勤怠,スケジュール

### 審査メモ（App Review への連絡）
ログインは不要です。初回起動で「新しく作る」を押すと、例の部門と時間のひな形が入った状態で始まります。「スタッフを追加」で数人を追加すると、シフト表・ホーム・印刷の機能を確認できます。サーバーとの通信は行わず、データは端末と利用者の iCloud（CloudKit）にのみ保存します。

1.1 で追加した機能について：
・希望休の申請：スタッフ用の申請ページ（https://facility-manager-phi.vercel.app/hotel-shift/request）は入力内容をサーバーに送らず、申請の内容を URL の「#」以降に入れたリンクを作るだけです。Associated Domains（applinks:facility-manager-phi.vercel.app）は、このリンクを押したときに SHIFT の「申請を受け取る」画面を開くために使います。お試し用のリンク（スタッフ「見本 花子」を登録すると名前が自動で選ばれます）：
https://facility-manager-phi.vercel.app/hotel-shift/r?openExternalBrowser=1#eyJ2IjoxLCJuIjoi6KaL5pysIOiKseWtkCIsInMiOiLopovmnKzjg5vjg4bjg6sg5pys6aSoIiwiZCI6WyIyMDI2LTEyLTAzIiwiMjAyNi0xMi0xMCJdLCJyIjoi5a-p5p-755So44Gu6KaL5pysIn0
・Face ID：設定 → 人件費 →「この端末で人件費・給与を隠す」をオンにしたときだけ、人件費を表示する前の本人確認に使います（確認は iOS が行い、アプリは生体情報を受け取りません）。

1.2 で追加した機能について：
・iCloud 共有：設定 →「シフト表の共有」から、Apple の共有の仕組み（CKShare）でほかの Apple ID の利用者を招待します。データは利用者の iCloud の中だけでやり取りし、運営者のサーバーは使いません。給与の記録は共有されません。
・最低賃金の表：起動時に1日1回まで、公開されている表（https://raw.githubusercontent.com/JunzoM/EldiaShift/main/minimum-wage.json）を読み込みます。読み込むだけで、利用者の情報は送りません。
・Mac 版：iPad と同じアプリです（Mac Catalyst）。店舗の画面の「見本のデータで試す」で、4店舗・各25人の見本が入ります。

## 画面写真
GitHub Actions の「App Store Screenshots」で作成し、`appstore-screenshots` ブランチに置く。
- ipad-13/：iPad 13インチ用
- iphone-6.9/：iPhone 6.9インチ用

### iPhone Duo（折りたたみ）
GitHub の環境にはまだ Duo のシミュレーターが無いので、Xcode 27 の入った Mac で撮る（任意。2027年4月からは iOS 27.1 SDK 以降で作ったアプリに必須になる予定）。

```
cd ~/Downloads/EldiaShift
bash scripts/duo-screenshots.sh
```

開いた画面（横向き 2853 × 2007）・閉じた画面（縦向き 1398 × 2034）それぞれ4枚（ホーム・月の表・日のタイムライン・印刷）が `shots/duo/` にできる。途中で、シミュレーターを「開いた状態の横向き」→「閉じた状態の縦向き」にするよう案内が出る。

### Duo での見え方
- 開いた画面：iPad と同じく左のサイドバー＋表。閉じた画面：iPhone と同じく下のタブ。開け閉めで自動で切り替わる
- 閉じたときにタブに無い項目（スタッフ・印刷・店舗）を開いていたら、設定・シフト表へ移る

## Mac 版（Mac Catalyst）

- iPad と同じアプリを Mac でも動かす（Mac Catalyst・「iPad に合わせて拡大縮小」）。バンドル ID は iOS と同じ `com.bestdelight.eldiashift`（`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`）なので、同じ App Store のアプリとして出し、**同じ Apple ID なら追加の購入は要らない**（ユニバーサル購入）
- Mac 用の権限は `Config/EldiaShift-mac.entitlements`（App Sandbox・ネットワーク（iCloud）・選んだファイルの読み書き・印刷・iCloud・プッシュ・Associated Domains）。iOS の権限ファイルは今までのまま
- Developer サイト：App ID で「Mac Catalyst」を有効にし、Mac 用のプロビジョニングプロファイルを作る（Xcode の自動署名なら Signing & Capabilities で Mac を選ぶだけ）。iCloud コンテナは iOS と同じ
- App Store Connect：同じアプリに macOS のビルドを足す（Xcode の Archive で「My Mac (Mac Catalyst)」を選んでアップロード）。Mac 用の画面写真（1280×800 以上）が要る
- ウインドウの最初の大きさ 1280×820、いちばん小さい大きさ 960×640
- メニュー：表示（⌘1〜⌘6）・印刷・出力（⌘P）・設定（⌘,）
- CI（Build）で、Mac Catalyst のビルドも毎回確かめる
- 実機で確かめること：iCloud 同期・共有の招待のリンクを Mac で開く・申請の取り込み用リンク（Associated Domains）・印刷・PDF の共有・写真と似顔絵・人件費を隠す設定（Touch ID）・⌘Z（文字の入力中とシフト表の上）

## 提出前のチェック
1. CloudKit Console で、開発環境のスキーマを本番へ反映（Deploy Schema Changes）
2. Xcode：Product → Archive → Distribute App → App Store Connect → Upload
3. App Store Connect でビルドを選び、上の内容と画面写真を入れて「審査へ提出」

### 1.1（ビルド 2）
- バージョン 1.1・ビルド 2。アップロードし直すときはビルド番号を上げる（Xcode の Build、または project の CURRENT_PROJECT_VERSION）
- CloudKit：1.1 で足した項目はすべて既存の JSON の中なので、スキーマの反映は不要
- Signing & Capabilities に Associated Domains（applinks:facility-manager-phi.vercel.app）が入っていることを確認（自動署名で App ID に機能が付く）
- facility-manager の `/.well-known/apple-app-site-association` が本番で開けること（appID：294N3Z6JPG.com.bestdelight.eldiashift）
- App Store Connect：「このバージョンの新機能」に上の文章、プロモーション用テキスト・説明を更新、審査メモに 1.1 の段落を追加
- App のプライバシー：「データを収集しない」のまま（給与・申請は端末と利用者の iCloud のみ。申請ページはサーバーに送らない）
- 画面写真：GitHub Actions の「App Store Screenshots」を main で実行し直すと、会社の見出し・人件費などの入った新しい画面になる
- 実機で確認：申請リンクから SHIFT が開く／人件費を隠す設定の Face ID／iPhone で受け取った申請が iPad に出る（iCloud 同期）／ホームの会社と店舗

### 1.2（ビルド 3）
- バージョン 1.2・ビルド 3。iOS と Mac で同じ番号（アップロードし直すときはビルド番号を上げる）
- CloudKit：**スキーマの反映が必要**。開発ビルドを一度動かして `PayRecord`（key・wages・updatedAt）と `CellRecord.note` を作り、共有を一度試してから、CloudKit Console で本番へ Deploy Schema Changes（`docs/sharing-test.md` の「前もって」）
- 実機で共有を確かめる：`docs/sharing-test.md` の 1〜8（Apple ID が違う2台）
- 最低賃金：`minimum-wage.json` と `MinimumWage.swift` の `bundled` が同じ年度・内容であること（2026年度でそろえ済み）
- Mac：Developer サイトで App ID の Mac Catalyst を有効化 → Xcode で「My Mac (Mac Catalyst)」を Archive してアップロード。Mac の実機で上の「Mac 版」の確認項目を見る
- 画面写真：GitHub Actions の「App Store Screenshots」を main で実行し直す（iPad・iPhone）。Mac 用（1280×800 以上）は Mac で撮る（⌘⇧4 → スペースでウインドウ）
- App Store Connect：「このバージョンの新機能」に 1.2 の文章、説明の「安心のデータ管理」を更新、審査メモに 1.2 の段落を追加、macOS のビルドを選ぶ
- App のプライバシー：「データを収集しない」のまま（最低賃金の表は読み込むだけ。共有は利用者の iCloud の中だけ）
