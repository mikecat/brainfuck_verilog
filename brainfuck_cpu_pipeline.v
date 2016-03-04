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

`define CPU_INST_RIGHT 8'h3e // >
`define CPU_INST_LEFT  8'h3c // <
`define CPU_INST_INC   8'h2b // +
`define CPU_INST_DEC   8'h2d // -
`define CPU_INST_WHILE 8'h5b // [
`define CPU_INST_WEND  8'h5d // ]
`define CPU_INST_IN    8'h2c // ,
`define CPU_INST_OUT   8'h2e // .

module brainfuck_cpu(clk, rst_i, initializing, ready, halted, prog_size,
	inst_addr, inst_load_data, jumpptr_addr, jumpptr_load_data,
	data_addr, data_load_data, data_store_data, data_we,
	input_data, input_valid, input_read, output_data, output_write, output_busy);
	parameter INST_ADDR_WIDTH = 15;
	parameter DATA_ADDR_WIDTH = 15;

	input clk;           // クロック (LOW→HIGH = 処理を進める)
	input rst_i;         // リセット (LOW = リセットする)
	output initializing; // 初期化中か
	output ready;        // 実行準備ができたか
	output halted;       // 実行が停止したか
	input [INST_ADDR_WIDTH:0] prog_size;             // プログラムのサイズ
	output [INST_ADDR_WIDTH-1:0] inst_addr;          // ロードする命令のアドレス
	input [7:0] inst_load_data;                      // ロードされる命令
	output [INST_ADDR_WIDTH-1:0] jumpptr_addr;       // ロードするジャンプ先アドレスのアドレス
	input [INST_ADDR_WIDTH-1:0] jumpptr_load_data;   // ロードされるジャンプ先アドレス
	output [DATA_ADDR_WIDTH-1:0] data_addr;          // ロードまたはストアするデータのアドレス
	input [7:0] data_load_data;                      // ロードされるデータ
	output [7:0] data_store_data;                    // ストアするデータ
	output data_we;                                  // データをストアするか (HIGH = する)
	input [7:0] input_data;   // 入力されるデータ
	input input_valid;        // 入力するデータがあるか (HIGH = ある)
	output input_read;        // 入力を読み込むか (HIGH = 読み込む)
	output [7:0] output_data; // 出力するデータ
	output output_write;      // 出力するか (HIGH = する)
	input output_busy;        // 出力を受け取れるか (LOW = 受け取れる)

	reg initializing;
	reg ready;
	reg halted;
	wire [INST_ADDR_WIDTH-1:0] inst_addr;
	wire [INST_ADDR_WIDTH-1:0] jumpptr_addr;
	wire [DATA_ADDR_WIDTH-1:0] data_addr;
	reg [7:0] data_store_data;
	reg data_we;
	reg input_read;
	reg [7:0] output_data;
	reg output_write;

	reg [INST_ADDR_WIDTH:0] pc;
	wire [INST_ADDR_WIDTH:0] next_pc;
	reg [DATA_ADDR_WIDTH-1:0] data_ptr;
	reg [7:0] inst_if, inst_ex;
	reg [INST_ADDR_WIDTH-1:0] jumpptr;
	reg stalled;
	reg [1:0] forwarding_count;

	assign inst_addr = next_pc;
	assign jumpptr_addr = next_pc;
	assign data_addr = data_ptr;

	// 直前に実行した命令がデータポインタの変更で、
	// 実行する命令がメモリを使用する命令のとき、ストールする (新しい位置のデータを読み込むため)
	wire do_stall_mem = (
		inst_ex == `CPU_INST_RIGHT || inst_ex == `CPU_INST_LEFT
	) && (
		inst_if == `CPU_INST_INC || inst_if == `CPU_INST_DEC ||
		inst_if == `CPU_INST_WHILE || inst_if == `CPU_INST_WEND ||
		inst_if == `CPU_INST_OUT
	);
	// 入力または出力が連続するとき、ストールする (入出力ポートの状態が更新されるのを待つため)
	wire do_stall_io = (inst_if == `CPU_INST_IN && inst_ex == `CPU_INST_IN) ||
		(inst_if == `CPU_INST_OUT && inst_ex == `CPU_INST_OUT);

	wire do_stall = (do_stall_mem | do_stall_io) & ~stalled;

	// 入出力ポートの準備ができていないとき、実行待機する
	wire io_wait = (inst_if == `CPU_INST_IN && ~input_valid) ||
		(inst_if == `CPU_INST_OUT && output_busy);

	// 直前またはその前に実行した命令がメモリに書き込む命令のとき、フォワーディングする
	wire do_forwarding = (forwarding_count > 0);
	// フォワーディングを反映したメモリの値
	wire [7:0] load_data = do_forwarding ? data_store_data : data_load_data;

	// ジャンプを行うか
	wire do_jump = (inst_if == `CPU_INST_WHILE && load_data == 0) ||
		(inst_if == `CPU_INST_WEND && load_data != 0);

	// 次に実行するのがメモリに書き込む命令か
	wire inst_if_mem = (inst_if == `CPU_INST_INC || inst_if == `CPU_INST_DEC || inst_if == `CPU_INST_IN);

	assign next_pc = (~rst_i || ~ready) ? 0 :
		(do_stall || io_wait) ? pc :
		do_jump ? jumpptr :
		(pc < prog_size) ? pc + 1 :
		pc;

	always @(posedge clk or negedge rst_i) begin
		if (~rst_i) begin
			initializing <= 0;
			ready <= 0;
			halted <= 0;
			data_store_data <= 0;
			data_we <= 0;
			input_read <= 0;
			output_data <= 0;
			output_write <= 0;

			pc <= 0;
			inst_if <= 0;
			inst_ex <= 0;
			jumpptr <= 0;
			stalled <= 0;
			forwarding_count <= 0;
		end else begin
			if (~ready) begin
				data_store_data <= 0;
				if (data_we) begin
					if (data_ptr == (1 << DATA_ADDR_WIDTH) - 1) begin
						// 初期化完了、実行開始
						data_we <= 0;
						ready <= 1;
						pc <= 0;
						data_ptr <= 0;
						inst_if <= 0;
						inst_ex <= 0;
						jumpptr <= 0;
						stalled <= 0;
						forwarding_count <= 0;
					end else begin
						data_ptr <= data_ptr + 1;
					end
				end else begin
					data_we <= 1;
					data_ptr <= 0;
				end
			end else begin
				if (do_stall) begin
					// ストール
					stalled <= 1;
					data_we <= 0;
					input_read <= 0;
					output_write <= 0;
					forwarding_count <= (forwarding_count > 0) ? forwarding_count - 1 : 0;
				end else if (io_wait) begin
					// 入出力待機
					data_we <= 0;
					input_read <= 0;
					output_write <= 0;
					forwarding_count <= (forwarding_count > 0) ? forwarding_count - 1 : 0;
				end else begin
					// 実行
					stalled <= 0;
					inst_ex <= inst_if;

					// 命令フェッチ
					if (do_jump) begin
						// ジャンプ
						inst_if <= 0;
						pc <= jumpptr;
					end else if (pc < prog_size) begin
						// 命令フェッチ
						inst_if <= inst_load_data;
						jumpptr <= jumpptr_load_data;
						pc <= pc + 1;
					end else begin
						// 実行終了
						inst_if <= 0;
						halted <= 1;
					end

					// 命令実行
					data_ptr <= (inst_if == `CPU_INST_RIGHT) ? data_ptr + 1 :
						(inst_if == `CPU_INST_LEFT) ? data_ptr - 1 :
						data_ptr;
					data_store_data <= (inst_if == `CPU_INST_INC) ? load_data + 1 :
						(inst_if == `CPU_INST_DEC) ? load_data - 1 :
						(inst_if == `CPU_INST_IN) ? input_data :
						data_store_data;
					data_we <= inst_if_mem;
					forwarding_count <= inst_if_mem ? 2 :
						(forwarding_count > 0) ? forwarding_count - 1 : 0;
					input_read <= inst_if == `CPU_INST_IN;
					output_write <= inst_if == `CPU_INST_OUT;
					output_data <= load_data;
				end
			end
		end
	end
endmodule
