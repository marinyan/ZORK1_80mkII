# Windows検証版

翻訳を実際のゲーム進行で確かめるための、Z-machine Version 3コンソール実行系です。
原作のゲームロジックは`references/zork1/COMPILED/zork1.z3`をそのまま使い、画面へ出る
Z文字列を外部の言語パックにある訳文へ差し替えます。訳文はEXEへ埋め込まないため、TSVを
書き換えてゲームを再起動するだけで別の表現を試せます。

Windows検証版のバージョンは`0.1.ビルド番号`で管理します。採番導入時の
リポジトリ履歴に合わせ、最初の番号は`0.1.13`です。番号は起動時とEXEの製品情報に
表示されます。`--version`だけを指定すると、バージョン番号だけを確認できます。

## 実行

.NET 10 SDKを用意し、リポジトリのルートから次を実行します。

```powershell
./tools/build-windows.ps1 -Run
```

自動スモークテストでは、日本語だけを入力し、次の流れを起動から終了まで確認します。

1. メールボックスを開け、チラシを取って読む。
2. 方角入力で家の裏へ回り、窓を開けて台所へ入る。
3. 居間でランタンを取り、明かりを点ける。
4. 持ち物と得点を表示し、ゲームを終了する。

```powershell
./tools/build-windows.ps1 -Smoke
```

全編の入力確認には、リンク先のwalkthroughをローカルへ取得してから通しプレイテストを
実行します。原作の乱数で戦闘死や泥棒による正解アイテムの盗難が起きるため、指定した回数を
完走するまで独立したゲームを再試行します。完走した周回では、得点350、石塚到達、全入力が
日本語であること、未認識語や文型エラーがないことを検査します。

```powershell
git clone https://github.com/johnesco/zork1-v2.git .local/zork1-v2-walkthrough
./tools/test-japanese-walkthrough.ps1 -Successes 3 -MaxAttempts 60
```

寄り道テストは同じ正解ルートの各地で、調べる・読む・聞くなどの任意行動を
追加します。原作の乱数でお宝が足りなくなる場合があるため、最後の探索地点まで到達し、
全入力が日本語で未認識語・文型エラー・既知の英語残りがなければ完了とします。

```powershell
./tools/test-japanese-walkthrough.ps1 -Explore -Successes 1 -MaxAttempts 60
```

## プレイログ

通常プレイでは、EXEと同じ場所の`logs`ディレクトリへセッションごとのJSON Linesログを
自動保存します。`output`イベントと`input`イベントが発生順に並び、入力イベントには
入力した文字列、Zorkへ渡した英語コマンド、日本語・英語・混在の区分が入ります。
セッション情報には忠実版を示す`edition: faithful`と、実行した言語パックも記録します。

```json
{"type":"input","rawInput":"レンチでボルトを回す","translatedInput":"turn bolt with wrench","zMachineInput":"turn bolt with wrench","inputKind":"japanese","translationApplied":true}
```

保存先は`--log-dir`で変更でき、`--no-log`を指定すると記録しません。

```powershell
./Zork1Japanese.exe --log-dir C:\work\zork-play-logs
./Zork1Japanese.exe --no-log
```

後段解析では、英語入力そのものを日本語入力の断念とは見なしません。序盤などを最初から
英語で進めた場合は除外し、同じ場所・対象で日本語入力を試して進展せず、その直後の英語入力で
状態が変わった一連の操作だけを「日本語入力を諦めた」候補として扱います。

フレームワーク依存の単一EXEは`build/windows-x64/Zork1Japanese.exe`へ、既定の日本語
パックは`build/windows-x64/lang/ja`へ生成します。

```powershell
./tools/build-windows.ps1 -Publish
```

生成物のEXEにはMITライセンスの原作Z-codeが埋め込まれます。リポジトリの`LICENSE`と
`references/zork1/LICENSE`の条件に従って扱ってください。`-Publish`では、
独自コードの`LICENSE.txt`と原作の`THIRD-PARTY-LICENSES/ZORK1-MIT.txt`も出力します。

## 外部言語パック

通常はEXEと同じ場所にある`lang/ja`を読みます。ここにあるTSVを直接編集し、ゲームを
再起動すれば変更が反映されます。再ビルドは不要です。

```text
Zork1Japanese.exe
lang/
  ja/
    messages.tsv
    objects.tsv
    rooms.tsv
    verbs.tsv
    directions.tsv
    input.tsv
    ui.tsv
    templates.tsv
  en/
    （templates.tsvを除く同じ7ファイル）
```

別のパック名は`--language`で、任意のディレクトリは`--language-dir`で指定できます。

```powershell
./Zork1Japanese.exe --language en
./Zork1Japanese.exe --language ja-first-person
./Zork1Japanese.exe --language-dir C:\work\zork-translation
```

リポジトリ内の訳文を出力先へコピーせず直接試す場合は、次のようにします。

```powershell
dotnet run --project windows/Zork1.Windows/Zork1.Windows.csproj -- `
  --language-dir translation/ja
```

各ファイルの役割は次のとおりです。

- `messages.tsv`、`objects.tsv`、`rooms.tsv`: 画面へ出す訳文
- `verbs.tsv`、`directions.tsv`: 入力する動詞と方角
- `input.tsv`: 「はい」「終了」など、優先したい入力語
- `ui.tsv`: ステータス行などWindows実行系固有の表示
- `templates.tsv`: 動的な物体名などを含む一文を日本語語順へ組み替える任意テンプレート

`templates.tsv`は、原文の一文を`{0}`、`{1}`などの可変部分付きで照合し、訳文側の
任意位置へ差し込みます。テンプレートに一致しない文は、従来どおり各TSVの断片訳を使います。

```powershell
dotnet run --project windows/Zork1.Windows/Zork1.Windows.csproj -- `
  --translate-output-line "The haft of your sword knocks out the troll."
```

表示用TSVは`english`と`translation`列を使います。既存の日本語パックだけは従来の
`japanese`列も後方互換で読み込めます。動詞と方角は`input`列を使い、日本語パックの
`japanese`列も同様に読み込めます。

すべて起動時に読み込まれます。`--language en`は外部の英語パックを使い、`--english`は
言語パックを一切通さず原作表示を確認する診断用です。英語パックは原典カタログから再生成できます。

```powershell
./tools/build-english-language-pack.ps1
```

## 日本語入力

入力は既存のZork Iパーサーへ渡す前に英語の辞書語へ変換します。現在は次の形を扱います。

- `北`、`南西`などの方角
- `見る`、`持ち物`、`終了`などの単独コマンド
- `ランプを取る`のような「物体名＋助詞＋動詞」
- `取る ランプ`のような空白区切り
- `置く 卵 棚`、`置く 卵 棚の中`、`棚の中に卵を置く`のような配置命令
- `剣 使う トロール`、`剣をトロールに使う`、`剣でトロールを攻撃`のような武器による攻撃
- `回す ボルト レンチ`、`レンチでボルトを回す`のような道具を伴う操作
- `棚から卵を取る`、`泥棒に卵を渡す`のような起点・相手を伴う操作
- `マッチで蝋燭を点ける`、`ポンプでプラスチックを膨らませる`のような道具を伴う操作
- `手すりにロープを結ぶ`のような二つの物体を結ぶ操作
- `瓶と袋を拾う`、`瓶、袋を落とす`のような複数対象の列挙
- `瓶と袋以外全部拾う`のような複数の例外を伴う一括操作
- `全部を棚の中に置く`、`棚から瓶以外全部取る`のような容器を伴う一括操作
- `瓶と袋を調べる`、`瓶と袋を押す`、`瓶と袋を泥棒に渡す`のような複数対象の操作

語彙は`verbs.tsv`、`directions.tsv`、`objects.tsv`、`input.tsv`から起動時に取り込みます。
`input.tsv`の「棚の中→in case」のような対応を使い、対象一つの「置く」はDROP、
置き場所の続く「置く」は`PUT ... IN/ON ...`に切り替えます。未登録の物体名や助詞の組合せは、
`input.tsv`への別名追加または入力構文の拡張が必要です。

複数対象は、原作パーサーが複数目的語を許している動詞だけで使用できます。そのため、
`全部開ける`や`全部読む`のような命令は、原作と同じく受け付けられません。

## 検証版で分かったこと

- ZIL文字列内の改行と字下げは、Z-codeでは空白一つに畳まれる。そのため原文照合では空白を
  正規化する必要がある。
- 一つの文章が複数のZ文字列、物体名、数値に分割される箇所では、断片ごとの直訳では日本語に
  ならない。TSVの分割単位を維持したまま語順を再構成する必要がある。
- 同じ英語断片に文脈別の訳が複数ある。空の接頭辞を含めた出現数で安全な共通訳を選んでいるが、
  全場面を完全に扱うにはZ文字列のアドレスまたは固有IDで訳文を引く必要がある。

この実行系は翻訳・パーサー設計の検証用です。セーブと復元、上段ウィンドウの厳密な再現、音響は
未実装です。
