# ZORK1_80mkII

Zork Iを日本語化し、PC-8001mkIIへ移植できるかを検証・実装するプロジェクトです。

## 前提

- 対象機はPC-8001mkII。
- 80S31などのフロッピーディスク装置は前提にしない。
- 配布・起動媒体はカセットテープを想定する。
- 起動後に必要なプログラムとゲームデータは、すべて本体RAMまたはGVRAM上に置く。
- 表示はテキスト画面と半角カタカナを中心にする。
- 開発用エミュレータとZ80アセンブラの実行ファイルは、このリポジトリへ含めない。

## 参照ソース

参照元はGit submoduleとして固定しています。

| パス | 参照元 | 用途 | ライセンス |
|---|---|---|---|
| `references/zork1` | [historicalsource/zork1](https://github.com/historicalsource/zork1) | Zork I原典およびビルド済みZ-codeの調査 | MIT |
| `references/upkr` | [exoticorn/upkr](https://github.com/exoticorn/upkr) | Z80向けデータ圧縮の検証 | Unlicense |

取得方法:

```sh
git clone --recurse-submodules https://github.com/marinyan/ZORK1_80mkII.git
```

すでにclone済みの場合:

```sh
git submodule update --init --recursive
```

参照submodule内は原則として直接変更しません。移植コード、変換処理、日本語データ、必要な差分は本リポジトリ側に置きます。

## 開発ツール

エミュレータとアセンブラ及び各種BIOSは各開発環境で別途用意します。将来のビルドスクリプトは、固定された個人環境の絶対パスではなく、環境変数またはローカル設定ファイルからツールの場所を受け取る方針です。

生成されたバイナリ、リスト、テープイメージは`build/`以下へ出力し、Gitでは管理しません。

## 現在の段階

まず次の技術検証を行います。

1. UpkrのZ80展開器をプロジェクト指定のアセンブラ方言へ移植する。
2. PC-8001mkIIのGVRAMから低位RAMへ圧縮データを展開する。
3. 半角カナ用の文字コード、辞書、入力パーサの最小構成を決める。
4. テープから主RAMとGVRAMへ全データを配置するローダを作る。

暫定的なメモリ案と圧縮実測値は[設計メモ](docs/design-notes.md)に記録しています。

ZILソースから抽出したシナリオ文とコマンド、および通常の日本語による仮訳は[翻訳データ](translation/README.md)にあります。

翻訳を原作のゲーム進行で確認するための[Windows検証版](windows/README.md)もあります。
原作Z-codeをコンソール実行ファイルで動かし、外部言語パックの訳文を表示します。日本語入力は
原作パーサーの辞書語へ変換します。日本語の`ja`と原文表示の`en`があり、TSVを編集して
再起動するだけで訳文を差し替えられます。

## ライセンス

本リポジトリ独自の移植コードと資料は[MIT License](LICENSE)で公開します。

参照submoduleと、そこから取り込んだコードには各参照元のライセンスおよび著作権表示も適用されます。Zork IのソースコードはCopyright (c) 2025 MicrosoftのMIT License、UpkrはUnlicenseです。ZORKの商標・ブランド権は、このMITライセンスには含まれません。公開範囲は[Microsoftの告知](https://opensource.microsoft.com/blog/2025/11/20/preserving-code-that-shaped-generations-zork-i-ii-and-iii-go-open-source/)も参照してください。
