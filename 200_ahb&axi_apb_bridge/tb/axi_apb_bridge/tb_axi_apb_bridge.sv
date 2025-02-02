/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_axi_apb_bridge();
	
	/** 配置参数 **/
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) apb_if_0(.clk(clk), .rst_n(rst_n));
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) apb_if_1(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) axi_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt1.drv", "apb_if", apb_if_0.slave);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "apb_if", apb_if_0.monitor);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "apb_if", apb_if_1.slave);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "apb_if", apb_if_1.monitor);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt3.drv", "axi_if", axi_if.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axi_if", axi_if.monitor);
		
		// 启动testcase
		run_test("AXIAPBBridgeCase0Test");
	end
	
	/** 待测模块 **/
	axi_apb_bridge_wrapper #(
		.apb_slave_n(2),
		.apb_s0_baseaddr(0),
		.apb_s0_range(4096),
		.apb_s1_baseaddr(4096),
		.apb_s1_range(4096),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axi_araddr(axi_if.araddr),
		.s_axi_arprot(axi_if.arprot),
		.s_axi_arvalid(axi_if.arvalid),
		.s_axi_arready(axi_if.arready),
		.s_axi_awaddr(axi_if.awaddr),
		.s_axi_awprot(axi_if.awprot),
		.s_axi_awvalid(axi_if.awvalid),
		.s_axi_awready(axi_if.awready),
		.s_axi_bresp(axi_if.bresp),
		.s_axi_bvalid(axi_if.bvalid),
		.s_axi_bready(axi_if.bready),
		.s_axi_rdata(axi_if.rdata),
		.s_axi_rresp(axi_if.rresp),
		.s_axi_rvalid(axi_if.rvalid),
		.s_axi_rready(axi_if.rready),
		.s_axi_wdata(axi_if.wdata),
		.s_axi_wstrb(axi_if.wstrb),
		.s_axi_wvalid(axi_if.wvalid),
		.s_axi_wready(axi_if.wready),
		
		.m0_apb_paddr(apb_if_0.paddr),
		.m0_apb_penable(apb_if_0.penable),
		.m0_apb_pwrite(apb_if_0.pwrite),
		.m0_apb_pprot(apb_if_0.pprot),
		.m0_apb_psel(apb_if_0.pselx),
		.m0_apb_pstrb(apb_if_0.pstrb),
		.m0_apb_pwdata(apb_if_0.pwdata),
		.m0_apb_pready(apb_if_0.pready),
		.m0_apb_pslverr(apb_if_0.pslverr),
		.m0_apb_prdata(apb_if_0.prdata),
		
		.m1_apb_paddr(apb_if_1.paddr),
		.m1_apb_penable(apb_if_1.penable),
		.m1_apb_pwrite(apb_if_1.pwrite),
		.m1_apb_pprot(apb_if_1.pprot),
		.m1_apb_psel(apb_if_1.pselx),
		.m1_apb_pstrb(apb_if_1.pstrb),
		.m1_apb_pwdata(apb_if_1.pwdata),
		.m1_apb_pready(apb_if_1.pready),
		.m1_apb_pslverr(apb_if_1.pslverr),
		.m1_apb_prdata(apb_if_1.prdata)
	);
	
endmodule
