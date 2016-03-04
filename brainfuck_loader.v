/*
Copyright (c) 2016 MikeCAT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

`default_nettype none

`define INITPHASE_INITPTR     0 // ジャンプ先アドレス情報を初期化
`define INITPHASE_SCAN        1 // 走査
`define INITPHASE_SEARCH      2 // 対応する閉じ括弧を検索
`define INITPHASE_WRITE       3 // 括弧の飛び先を書き込み
`define INITPHASE_CHECK_FETCH 4 // 閉じ括弧に対応する括弧の情報を読み込む
`define INITPHASE_CHECK       5 // 閉じ括弧に対応する括弧があるかをチェック
`define INITPHASE_ERROR       6 // 文法エラーを検出

module brainfuck_loader(clk, rst_i, soft_reset, enable, initializing, ready, halted, prog_size,
	inst_addr, inst_load_data, inst_store_data, inst_we,
	jumpptr_addr, jumpptr_load_data, jumpptr_store_data, jumpptr_we,
	input_data, input_valid, input_read, output_data, output_write, output_busy);
	parameter INST_ADDR_WIDTH = 15;

	input clk;           // クロック (LOW→HIGH = 処理を進める)
	input rst_i;         // リセット (LOW = リセットする)
	input soft_reset;    // ソフトリセット (HIGH = リセットする)
	input enable;        // プログラム書き込みモードにするか (HIGH = する)
	output initializing; // 初期化中か
	output ready;        // 実行準備ができたか
	output halted;       // 実行が停止したか
	output [INST_ADDR_WIDTH:0] prog_size;            // プログラムのサイズ
	output [INST_ADDR_WIDTH-1:0] inst_addr;          // ロードまたはストアする命令のアドレス
	input [7:0] inst_load_data;                      // ロードされる命令
	output [7:0] inst_store_data;                    // ストアする命令
	output inst_we;                                  // 命令をストアするか (HIGH = する)
	output [INST_ADDR_WIDTH-1:0] jumpptr_addr;       // ロードまたはストアするジャンプ先アドレスのアドレス
	input [INST_ADDR_WIDTH-1:0] jumpptr_load_data;   // ロードされるジャンプ先アドレス
	output [INST_ADDR_WIDTH-1:0] jumpptr_store_data; // ストアするジャンプ先アドレス
	output jumpptr_we;                               // ジャンプ先アドレスをストアするか (HIGH = する)
	input [7:0] input_data;   // 入力されるデータ
	input input_valid;       // 入力するデータがあるか (HIGH = ある)
	output input_read;        // 入力を読み込むか (HIGH = 読み込む)
	output [7:0] output_data; // 出力するデータ
	output output_write;      // 出力するか (HIGH = する)
	input output_busy;        // 出力を受け取れるか (LOW = 受け取れる)

	reg initializing;
	reg ready;
	wire halted;
	reg [INST_ADDR_WIDTH-1:0] inst_addr;
	reg [7:0] inst_store_data;
	reg inst_we;
	reg [INST_ADDR_WIDTH-1:0] jumpptr_addr;
	reg [INST_ADDR_WIDTH-1:0] jumpptr_store_data;
	reg jumpptr_we;
	reg input_read;
	reg [7:0] output_data;
	reg output_write;

	reg [2:0] initialize_phase; // 初期化の種類
	reg [INST_ADDR_WIDTH:0] search_pc;    // 対応する括弧を探す時のポインタ
	reg [INST_ADDR_WIDTH:0] search_count; // 対応する括弧を探す時のカウンタ

	reg [INST_ADDR_WIDTH:0] pc;    // プログラムカウンタ
	reg [INST_ADDR_WIDTH:0] prog_size; // プログラムサイズ
	reg fetch_done; // 入力を読み込んだか

	wire pc_overflow = pc[INST_ADDR_WIDTH]; // プログラムカウンタがオーバーフローしたか

	assign halted = initializing ? (initialize_phase == `INITPHASE_ERROR) : pc_overflow;

	always @(posedge clk or negedge rst_i) begin
		if (~rst_i) begin
			search_pc <= 0;
			search_count <= 0;
			initialize_phase <= `INITPHASE_INITPTR;
			pc <= 0;
			prog_size <= 0;
			initializing <= 0;
			ready <= 0;
			inst_addr <= 0;
			inst_store_data <= 0;
			inst_we <= 0;
			jumpptr_addr <= 0;
			jumpptr_store_data <= 0;
			jumpptr_we <= 0;
			input_read <= 0;
			output_data <= 0;
			output_write <= 0;
		end else begin
			if (initializing) begin
				// 初期化中
				case (initialize_phase)
				`INITPHASE_INITPTR: begin
					if (pc + 1 == prog_size) begin
						// 最後まで書き込んだ
						jumpptr_we <= 0;
						initialize_phase <= `INITPHASE_SCAN;
						pc <= 0;
						inst_addr <= 0; // 最初の命令を読む
					end else begin
						jumpptr_addr <= pc + 1;
						jumpptr_store_data <= pc + 1;
						pc <= pc + 1;
					end
				end
				`INITPHASE_SCAN: begin
					jumpptr_we <= 0;
					if (inst_load_data  == 'h5b) begin // 括弧
						initialize_phase <= `INITPHASE_SEARCH;
						search_count <= 1; // 次のクロックで読みだすのは括弧の次なので、この括弧は数に含める
						search_pc <= pc + 1;
						inst_addr <= pc + 1; // PCには次のクロックで読み出すアドレスが入っている
					end else if (inst_load_data == 'h5d) begin // 閉じ括弧
						initialize_phase <= `INITPHASE_CHECK_FETCH;
						jumpptr_addr <= pc - 1;
					end else begin
						if (pc + 1 == prog_size) begin
							// 最後まで走査したので、実行モードに切り替え
							initializing <= 0;
							ready <= 1;
							pc <= 0;
							inst_we <= 0;
							jumpptr_we <= 0;
							input_read <= 0;
							output_write <= 0;
						end else begin
							pc <= pc + 1; // これは次のクロックで読み出すアドレスを計算する
							inst_addr <= pc + 1;
						end
					end
				end
				`INITPHASE_SEARCH: begin
					if (inst_load_data == 'h5d) begin // 閉じ括弧
						search_count <= search_count - 1;
						if (search_count == 1) begin
							// 対応する閉じ括弧が見つかった
							// 閉じ括弧の位置に括弧の位置を書き込む
							jumpptr_addr <= search_pc - 1;
							jumpptr_we <= 1;
							jumpptr_store_data <= pc - 1;
							initialize_phase <= `INITPHASE_WRITE;
							inst_addr <= pc;
						end else begin
							if (search_pc + 1 == prog_size) begin
								// 最後まで検索したけど対応する閉じ括弧が見つからなかった
								initialize_phase <= `INITPHASE_ERROR;
								inst_addr <= pc - 1;
							end else begin
								search_pc <= search_pc + 1;
								inst_addr <= search_pc + 1;
							end
						end
					end else begin
						if (inst_load_data == 'h5b) begin // 括弧
							search_count <= search_count + 1;
						end
						if (search_pc + 1 == prog_size) begin
							// 最後まで検索したけど対応する閉じ括弧が見つからなかった
							initialize_phase <= `INITPHASE_ERROR;
							inst_addr <= pc - 1;
						end else begin
							search_pc <= search_pc + 1;
							inst_addr <= search_pc + 1;
						end
					end
				end
				`INITPHASE_WRITE: begin
					// 括弧の位置に閉じ括弧の位置を書き込んで走査に戻る
					jumpptr_addr <= pc - 1;
					jumpptr_we <= 1;
					jumpptr_store_data <= search_pc - 1;
					initialize_phase <= `INITPHASE_SCAN;
					if (pc + 1 == prog_size) begin
						// 最後まで走査したので、実行モードに切り替え
						initializing <= 0;
						ready <= 1;
						pc <= 0;
						inst_we <= 0;
						jumpptr_we <= 0;
						input_read <= 0;
						output_write <= 0;
					end else begin
						pc <= pc + 1; // これは次のクロックで読み出すアドレスを計算する
						inst_addr <= pc + 1;
					end
				end
				`INITPHASE_CHECK_FETCH: begin
					// 指定したアドレスのデータが取り込まれるのを待つ
					initialize_phase <= `INITPHASE_CHECK;
				end
				`INITPHASE_CHECK: begin
					if (jumpptr_load_data == pc) begin
						// 対応する括弧が無い、NG
						initialize_phase <= `INITPHASE_ERROR;
						inst_addr <= pc - 1;
					end else begin
						// OK
						initialize_phase <= `INITPHASE_SCAN;
						if (pc + 1 == prog_size) begin
							// 最後まで走査したので、実行モードに切り替え
							initializing <= 0;
							ready <= 1;
							pc <= 0;
							inst_we <= 0;
							jumpptr_we <= 0;
							input_read <= 0;
							output_write <= 0;
						end else begin
							pc <= pc + 1; // これは次のクロックで読み出すアドレスを計算する
							inst_addr <= pc + 1;
						end
					end
				end
				`INITPHASE_ERROR: begin
					// 何もしない
				end
				endcase
			end else if (~ready & ~enable) begin
				// 初期化開始
				initializing <= 1;
				initialize_phase <= `INITPHASE_INITPTR;
				pc <= 0;
				search_count <= 0;
				prog_size <= pc; // 書き込み位置をプログラムサイズとして保存
				jumpptr_addr <= 0; // 最初のデータを書き込む
				jumpptr_store_data <= 0;
				jumpptr_we <= 1;
				inst_we <= 0;
				input_read <= 0;
				output_write <= 0;
			end else begin
				// プログラム書き込みモード
				jumpptr_we <= 0;
				if (fetch_done) begin
					fetch_done <= 0;
					input_read <= 0; // 読み込んだ直後はinput_validを判定できないので、読み込まない
					if (~pc_overflow) begin // プログラムメモリに空きがあるなら
						inst_addr <= pc[INST_ADDR_WIDTH-1:0]; // 書き込むアドレスを指定する
						inst_we <= 1; // 読み込んだデータを書き込む
						pc <= pc + 1; // 書き込み先を進める
					end else begin
						inst_we <= 0; // データを書き込まない
					end
				end else begin
					inst_we <= 0; // データを書き込まない
					if (input_valid) begin
						inst_store_data <= input_data; // 入力データを読み込む
						fetch_done <= 1; // 入力データを読み込んだフラグを立てる
						input_read <= 1; // 入力データを読み込むことを知らせる
					end else begin
						input_read <= 0; // 入力データを読み込まない
						fetch_done <= 0; // 入力データを読み込んでない
					end
				end
			end
		end
	end
endmodule
