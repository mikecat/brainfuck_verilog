Brainfu*kインタプリタ
---------------------

## これは何?

Verilogで書かれたBrainfu*kインタプリタです。

プログラムを読み込み、ジャンプ先を決める前処理をした後、実行します。

## ビルド方法

[Icarus Verilog](http://iverilog.icarus.com/)で動作確認しています。

基本的には`make`コマンド一発でビルドできるはずです。

## 実行方法

実行する前に、プログラムデータと入力データを用意してください。

プログラムデータは`program_hex.txt`、入力データは`input_hex.txt`として保存します。

データは`perl data2mem.pl < (変換元のファイル) > (変換結果を保存するファイル)`として変換してください。

データを用意したら、`vvp brainfuck`または`vvp brainfuck_pipeline`として実行できるはずです。

`brainfuck`は3クロックで1命令を実行するバージョン、
`brainfuck_pipeline`はより効率のよいバージョンです。

## ライセンス

This software is released under [the MIT License](https://opensource.org/licenses/MIT).
