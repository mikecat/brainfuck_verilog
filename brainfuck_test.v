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

`timescale 1ns/1ns
`default_nettype none

module brainfuck_test;
	reg [31:0] clock_count, startexec_time;
	reg clk;
	reg rst_i;
	reg cpu_reset_i;
	reg program;

	wire initializing, ready, halted;
	wire [7:0] input_data, output_data;
	wire input_valid, input_read, output_write, output_busy;
	wire [7:0] input_pdata, input_idata;
	wire input_pvalid, input_pread, input_ivalid, input_iread;

	wire input_mode = ~program & ready;
	assign input_data = input_mode ? input_idata : input_pdata;
	assign input_valid = input_mode ? input_ivalid : input_pvalid;
	assign input_pread = ~input_mode & input_read;
	assign input_iread = input_mode & input_read;

	brainfuck bf (.clk(clk), .rst_i(rst_i), .cpu_reset_i(cpu_reset_i), .program(program),
		.initializing(initializing), .ready(ready), .halted(halted),
		.input_data(input_data), .input_valid(input_valid), .input_read(input_read),
		.output_data(output_data), .output_write(output_write), .output_busy(output_busy));

	input_provider #(.filename("program_hex.txt")) ip_program (.clk(clk), .rst_i(rst_i),
		.input_data(input_pdata), .input_valid(input_pvalid), .input_read(input_pread));

	input_provider #(.filename("input_hex.txt")) ip_input (.clk(clk), .rst_i(rst_i),
		.input_data(input_idata), .input_valid(input_ivalid), .input_read(input_iread));

	always @(posedge clk) begin
		if (output_write) begin
			$write("%c", output_data);
		end
	end

	assign output_busy = 0;

	always #25 begin
		clk <= ~clk; // 20MHz
	end

	initial begin
		$dumpfile("brainfuck_test.vcd");
		$dumpvars(0, brainfuck_test);

		clock_count <= 0;
		startexec_time <= 0;
		clk <= 1;
		rst_i <= 0;
		cpu_reset_i <= 1;
		program <= 1;
		#100;
		rst_i <= 1;
	end

	always @(posedge clk) begin
		clock_count <= clock_count + 1;
	end

	always @(negedge input_pvalid) begin
		#400;
		program <= 0;
	end

	always @(posedge ready) begin
		startexec_time <= clock_count;
	end

	always @(posedge halted) begin
		$display("\nelapsed time = %d clocks", clock_count - startexec_time);
		#400;
		$finish;
	end

	always #40000000 begin
		$finish;
	end

endmodule

module input_provider(clk, rst_i, input_data, input_valid, input_read);
	parameter filename = "data.txt";

	input clk;
	input rst_i;
	output [7:0] input_data;
	output input_valid;
	input input_read;

	reg [7:0] input_data;
	reg input_valid;
	reg [15:0] limit;
	reg [15:0] cnt;
	reg [7:0] mem[0:65535];

	// 入力データは最初の2バイトに長さ(リトルエンディアン)、その次からデータ
	initial begin
		$readmemh(filename, mem);
		limit = {mem[1], mem[0]};
	end

	always @(posedge clk or negedge rst_i) begin
		if (~rst_i) begin
			input_data <= (limit > 0) ? mem[2] : 0;
			cnt <= 0;
			input_valid <= (limit > 0);
		end else begin
			if (input_read) begin
				if (cnt + 1 < limit) begin
					input_data <= mem[cnt + 1 + 2];
					cnt <= cnt + 1;
				end else begin
					input_data <= 0;
					input_valid <= 0;
				end
			end
		end
	end

endmodule
