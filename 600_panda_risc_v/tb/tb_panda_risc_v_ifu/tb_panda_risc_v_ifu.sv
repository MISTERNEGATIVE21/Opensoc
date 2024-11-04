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

module tb_panda_risc_v_ifu();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer imem_access_timeout_th = 16; // 指令总线访问超时周期数(必须>=1)
	localparam integer inst_addr_alignment_width = 32; // 指令地址对齐位宽(16 | 32)
	localparam RST_PC = 32'h0000_0000; // 复位时的PC
	// 仿真模型配置
	localparam integer imem_depth = 1024;
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(128), .user_width(4)) s_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(128), .user_width(4)).slave)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(128), .user_width(4)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("PandaRiscVIfuCase0Test");
	end
	
	/** 待测模块 **/
	// 系统复位输出
	wire sys_resetn;
	// 软件复位请求
	reg sw_reset;
	// 冲刷请求
	reg flush_req;
	reg[31:0] flush_addr;
	// 数据相关性
	wire[4:0] rs1_id; // rs1索引
	wire rs1_raw_dpc; // RS1有RAW相关性(标志)
	// 专用于JALR指令的通用寄存器堆读端口
	wire[31:0] jalr_x1_v; // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器读端口#0
	wire jalr_reg_file_rd_p0_req; // 读请求
	wire[4:0] jalr_rd_p0_addr; // 读地址
	wire jalr_reg_file_rd_p0_grant; // 读许可
	wire[31:0] jalr_reg_file_rd_p0_dout; // 读数据
	// 指令ICB主机
	// 命令通道
	wire[31:0] m_icb_cmd_inst_addr;
	wire m_icb_cmd_inst_read;
	wire[31:0] m_icb_cmd_inst_wdata;
	wire[3:0] m_icb_cmd_inst_wmask;
	wire m_icb_cmd_inst_valid;
	wire m_icb_cmd_inst_ready;
	// 响应通道
	wire[31:0] m_icb_rsp_inst_rdata;
	wire m_icb_rsp_inst_err;
	wire m_icb_rsp_inst_valid;
	wire m_icb_rsp_inst_ready;
	// 指令总线访问超时标志
	wire ibus_timeout;
	
	assign s_axis_if.last = 1'b1;
	
	assign rs1_raw_dpc = 1'b0;
	
	assign jalr_x1_v = imem_depth / 2;
	assign jalr_reg_file_rd_p0_grant = jalr_reg_file_rd_p0_req;
	assign jalr_reg_file_rd_p0_dout = imem_depth / 2;
	
	// 软件复位/冲刷请求
	initial
	begin
		sw_reset <= 1'b0;
		flush_req <= 1'b0;
		flush_addr <= 0;
		
		# simulation_delay;
		
		# (clk_p * 20);
		
		flush_req <= 1'b1;
		flush_addr <= 124;
		
		# clk_p;
		
		flush_req <= 1'b0;
		flush_addr <= 0;
	end
	
	panda_risc_v_ifu #(
		.imem_access_timeout_th(imem_access_timeout_th),
		.inst_addr_alignment_width(inst_addr_alignment_width),
		.RST_PC(RST_PC),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.ext_resetn(rst_n),
		.sys_resetn(sys_resetn),
		
		.sw_reset(sw_reset),
		
		.flush_req(flush_req),
		.flush_addr(flush_addr),
		
		.rs1_id(rs1_id),
		.rs1_raw_dpc(rs1_raw_dpc),
		
		.jalr_x1_v(jalr_x1_v),
		.jalr_reg_file_rd_p0_req(jalr_reg_file_rd_p0_req),
		.jalr_rd_p0_addr(jalr_rd_p0_addr),
		.jalr_reg_file_rd_p0_grant(jalr_reg_file_rd_p0_grant),
		.jalr_reg_file_rd_p0_dout(jalr_reg_file_rd_p0_dout),
		
		.m_icb_cmd_inst_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_rsp_inst_ready),
		
		.if_res_data(s_axis_if.data),
		.if_res_msg(s_axis_if.user),
		.if_res_valid(s_axis_if.valid),
		.if_res_ready(s_axis_if.ready),
		
		.ibus_timeout(ibus_timeout)
	);
	
	/** 仿真模型 **/
	// SRAM存储器主接口
	wire bram_clk;
    wire bram_rst;
    wire bram_en;
    wire[3:0] bram_wen;
    wire[29:0] bram_addr;
    wire[31:0] bram_din;
    wire[31:0] bram_dout;
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("false"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(simulation_delay)
	)icb_sram_ctrler_u(
		.s_icb_aclk(clk),
		.s_icb_aresetn(sys_resetn),
		
		.s_icb_cmd_addr(m_icb_cmd_inst_addr),
		.s_icb_cmd_read(m_icb_cmd_inst_read),
		.s_icb_cmd_wdata(m_icb_cmd_inst_wdata),
		.s_icb_cmd_wmask(m_icb_cmd_inst_wmask),
		.s_icb_cmd_valid(m_icb_cmd_inst_valid),
		.s_icb_cmd_ready(m_icb_cmd_inst_ready),
		.s_icb_rsp_rdata(m_icb_rsp_inst_rdata),
		.s_icb_rsp_err(m_icb_rsp_inst_err),
		.s_icb_rsp_valid(m_icb_rsp_inst_valid),
		.s_icb_rsp_ready(m_icb_rsp_inst_ready),
		
		.bram_clk(bram_clk),
		.bram_rst(bram_rst),
		.bram_en(bram_en),
		.bram_wen(bram_wen),
		.bram_addr(bram_addr),
		.bram_din(bram_din),
		.bram_dout(bram_dout)
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(32),
		.mem_depth(imem_depth),
		.INIT_FILE("no_init"),
		.byte_write_mode("true"),
		.simulation_delay(simulation_delay)
	)bram_single_port_u(
		.clk(bram_clk),
		
		.en(bram_en),
		.wen(bram_wen),
		.addr(bram_addr),
		.din(bram_din),
		.dout(bram_dout)
	);
	
	/** 生成待测指令 **/
	RiscVInstTrans inst_trans;
	integer fid;
	
	initial
	begin
		inst_trans = new();
		fid = $fopen("inst.txt", "w");
		
		for(int i = 0;i < imem_depth;i++)
		begin
			assert(inst_trans.randomize() with{
				csr_addr <= 15;
				
				if((inst_type == JAL) || (inst_type == JALR) || 
					(inst_type == BEQ) || (inst_type == BNE) || 
					(inst_type == BLT) || (inst_type == BGE) || 
					(inst_type == BLTU) || (inst_type == BGEU))
					(imm >= -i) && (imm <= (imem_depth - 1 - i)) && (imm[1:0] == 2'b00);
				else
					(imm >= -256) && (imm <= 255);
			}) else $fatal("inst_trans failed to randomize!");
			
			bram_single_port_u.mem[i] = inst_trans.inst;
			
			$fdisplay(fid, "%d %s %7.7b %5.5b %5.5b %3.3b %5.5b %7.7b", 
				i * 4, 
				inst_trans.risc_v_inst_type_to_string(inst_trans.inst_type), 
				inst_trans.inst[31:25], inst_trans.inst[24:20], 
				inst_trans.inst[19:15], inst_trans.inst[14:12], 
				inst_trans.inst[11:7], inst_trans.inst[6:0]);
		end
		
		$display("Inst generated!");
		$fclose(fid);
	end
	
endmodule
