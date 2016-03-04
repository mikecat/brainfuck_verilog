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

module brainfuck(clk, rst_i, cpu_reset_i, program, initializing, ready, halted,
	input_data, input_valid, input_read, output_data, output_write, output_busy);
	parameter INST_ADDR_WIDTH = 15;
	parameter DATA_ADDR_WIDTH = 15;

	input clk;
	input rst_i;
	input cpu_reset_i;
	input program;
	output initializing;
	output ready;
	output halted;
	input [7:0] input_data;
	input input_valid;
	output input_read;
	output [7:0] output_data;
	output output_write;
	input output_busy;

	reg program_sync;

	always @(posedge clk) begin
		program_sync <= program;
	end

	wire [7:0] iram_read, iram_write, dram_read, dram_write;
	wire [INST_ADDR_WIDTH-1:0] jram_read, jram_write;
	wire [INST_ADDR_WIDTH-1:0] iram_addr, jram_addr;
	wire [DATA_ADDR_WIDTH-1:0] dram_addr;
	wire iram_we, jram_we, dram_we;

	// 命令メモリ
	ram #(.ADDR_WIDTH(INST_ADDR_WIDTH), .DATA_WIDTH(8)) iram (
		.clk(clk), .data_read(iram_read), .data_write(iram_write), .addr(iram_addr), .we(iram_we));
	// ジャンプ先メモリ
	ram #(.ADDR_WIDTH(INST_ADDR_WIDTH), .DATA_WIDTH(INST_ADDR_WIDTH)) jram (
		.clk(clk), .data_read(jram_read), .data_write(jram_write), .addr(jram_addr), .we(jram_we));
	// データメモリ
	ram #(.ADDR_WIDTH(DATA_ADDR_WIDTH), .DATA_WIDTH(8)) dram (
		.clk(clk), .data_read(dram_read), .data_write(dram_write), .addr(dram_addr), .we(dram_we));

	wire load_initializing, load_ready, load_halted;
	wire [INST_ADDR_WIDTH:0] prog_size;
	wire load_iwe, load_jwe;
	wire [INST_ADDR_WIDTH-1:0] load_iaddr, load_jaddr;
	wire load_input_read, load_output_write;
	wire [7:0] load_output_data;
	wire cpu_initializing, cpu_ready, cpu_halted;
	wire [INST_ADDR_WIDTH-1:0] cpu_iaddr, cpu_jaddr;
	wire cpu_input_read,  cpu_output_write;
	wire [7:0] cpu_output_data;

	wire bus_load = program_sync | ~load_ready;

	assign initializing = bus_load ? load_initializing : cpu_initializing;
	assign ready = load_ready & cpu_ready;
	assign halted = bus_load ? load_halted : cpu_halted;
	assign iram_addr = bus_load ? load_iaddr : cpu_iaddr;
	assign jram_addr = bus_load ? load_jaddr : cpu_jaddr;
	assign iram_we = bus_load & load_iwe;
	assign jram_we = bus_load & load_jwe;
	assign input_read = bus_load ? load_input_read : cpu_input_read;
	assign output_data = bus_load ? load_output_data : cpu_output_data;
	assign output_write = bus_load ? load_output_write : cpu_output_write;

	// プログラムローダー
	// CPUからは命令やジャンプ先を書き込まないので、書き込むデータはRAMと直結してよい
	brainfuck_loader #(.INST_ADDR_WIDTH(INST_ADDR_WIDTH))
		loader (.clk(clk), .rst_i(rst_i), .enable(program_sync),
			.initializing(load_initializing), .ready(load_ready), .halted(load_halted), .prog_size(prog_size),
			.inst_addr(load_iaddr), .inst_load_data(iram_read), .inst_store_data(iram_write), .inst_we(load_iwe),
			.jumpptr_addr(load_jaddr), .jumpptr_load_data(jram_read),
			.jumpptr_store_data(jram_write), .jumpptr_we(load_jwe),
			.input_data(input_data), .input_valid(input_valid), .input_read(load_input_read),
			.output_data(load_output_data), .output_write(load_output_write), .output_busy(output_busy));

	// CPU
	brainfuck_cpu #(.INST_ADDR_WIDTH(INST_ADDR_WIDTH), .DATA_ADDR_WIDTH(DATA_ADDR_WIDTH))
		cpu (.clk(clk), .rst_i(rst_i & cpu_reset_i & ~bus_load),
			.initializing(cpu_initializing), .ready(cpu_ready), .halted(cpu_halted), .prog_size(prog_size),
			.inst_addr(cpu_iaddr), .inst_load_data(iram_read),
			.jumpptr_addr(cpu_jaddr), .jumpptr_load_data(jram_read),
			.data_addr(dram_addr), .data_load_data(dram_read), .data_store_data(dram_write), .data_we(dram_we),
			.input_data(input_data), .input_valid(input_valid), .input_read(cpu_input_read),
			.output_data(cpu_output_data), .output_write(cpu_output_write), .output_busy(output_busy));
endmodule

module ram(clk, data_read, data_write, addr, we);
	parameter ADDR_WIDTH = 15;
	parameter DATA_WIDTH = 8;

	input clk;
	output [DATA_WIDTH-1:0] data_read;
	input [DATA_WIDTH-1:0] data_write;
	input [ADDR_WIDTH-1:0] addr;
	input we;

	reg [DATA_WIDTH-1:0] data_read;
	reg [DATA_WIDTH-1:0] mem[0:(1<<ADDR_WIDTH)-1];

	always @(posedge clk) begin
		data_read <= mem[addr];
		if (we) mem[addr] <= data_write;
	end
endmodule
