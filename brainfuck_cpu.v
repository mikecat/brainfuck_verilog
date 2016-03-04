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

`define CPU_PHASE_IF 0
`define CPU_PHASE_EX 1
`define CPU_PHASE_WB 2

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
	reg [DATA_ADDR_WIDTH-1:0] data_ptr;
	reg [1:0] phase;
	reg [7:0] inst;
	reg [INST_ADDR_WIDTH-1:0] jumpptr;

	assign inst_addr = pc;
	assign jumpptr_addr = pc;
	assign data_addr = data_ptr;

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
			phase <= `CPU_PHASE_IF;
			inst <= 0;
			jumpptr <= 0;
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
						phase <= `CPU_PHASE_IF;
						inst <= 0;
						jumpptr <= 0;
					end else begin
						data_ptr <= data_ptr + 1;
					end
				end else begin
					data_we <= 1;
					data_ptr <= 0;
				end
			end else begin
				case (phase)
				`CPU_PHASE_IF: begin
					data_we <= 0;
					input_read <= 0;
					output_write <= 0;
					if (pc < prog_size) begin
						inst <= inst_load_data;
						jumpptr <= jumpptr_load_data;
						pc <= pc + 1;
						phase <= `CPU_PHASE_EX;
					end else begin
						inst <= 0;
						halted <= 1;
					end
				end
				`CPU_PHASE_EX: begin
					case (inst)
					`CPU_INST_RIGHT: begin
						data_ptr <= data_ptr + 1;
						phase <= `CPU_PHASE_WB;
					end
					`CPU_INST_LEFT: begin
						data_ptr <= data_ptr - 1;
						phase <= `CPU_PHASE_WB;
					end
					`CPU_INST_INC: begin
						data_store_data <= data_load_data + 1;
						data_we <= 1;
						phase <= `CPU_PHASE_WB;
					end
					`CPU_INST_DEC: begin
						data_store_data <= data_load_data - 1;
						data_we <= 1;
						phase <= `CPU_PHASE_WB;
					end
					`CPU_INST_WHILE: begin
						if (data_load_data == 0) begin
							pc <= jumpptr;
						end
						phase <= `CPU_PHASE_WB;
					end
					`CPU_INST_WEND: begin
						if (data_load_data != 0) begin
							pc <= jumpptr;
						end
						phase <= `CPU_PHASE_WB;
					end
					`CPU_INST_IN: begin
						if (input_valid) begin
							data_store_data <= input_data;
							data_we <= 1;
							input_read <= 1;
							phase <= `CPU_PHASE_WB;
						end
					end
					`CPU_INST_OUT: begin
						if (~output_busy) begin
							output_data <= data_load_data;
							output_write <= 1;
							phase <= `CPU_PHASE_WB;
						end
					end
					default: begin
						phase <= `CPU_PHASE_WB;
					end
					endcase
				end
				`CPU_PHASE_WB: begin
					case (inst)
					`CPU_INST_RIGHT: begin
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_LEFT: begin
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_INC: begin
						data_we <= 0;
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_DEC: begin
						data_we <= 0;
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_WHILE: begin
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_WEND: begin
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_IN: begin
						data_we <= 0;
						input_read <= 0;
						phase <= `CPU_PHASE_IF;
					end
					`CPU_INST_OUT: begin
						output_write <= 0;
						phase <= `CPU_PHASE_IF;
					end
					default: begin
						phase <= `CPU_PHASE_IF;
					end
					endcase
				end
				endcase
			end
		end
	end
endmodule
