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
/********************************************************************
本模块: 取指单元

描述:
对取指结果进行预译码和静态分支预测, 
将取指结果传递到下级, 同时发起新的指令存储器访问请求, 并更新PC

由指令总线控制单元将指令存储器访问请求转换为指令ICB主机上的传输

若当前指令是JALR, 则需要根据RS1读基地址

注意：
无

协议:
ICB MASTER
REQ/ACK
REQ/GRANT

作者: 陈家耀
日期: 2025/03/14
********************************************************************/


module panda_risc_v_ifu #(
	parameter integer imem_access_timeout_th = 16, // 指令总线访问超时周期数(必须>=1)
	parameter integer inst_addr_alignment_width = 32, // 指令地址对齐位宽(16 | 32)
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	// 系统复位输入
	input wire sys_resetn,
	
	// 复位时的PC
	input wire[31:0] rst_pc,
	
	// 系统复位请求
	input wire sys_reset_req,
	// 冲刷请求
	input wire flush_req,
	input wire[31:0] flush_addr,
	// 复位应答
	output wire rst_ack,
	// 冲刷应答
	output wire flush_ack,
	
	// 数据相关性
	output wire[4:0] rs1_id, // RS1索引
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	
	// 专用于JALR指令的通用寄存器堆读端口
	input wire[31:0] jalr_x1_v, // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器堆读端口#0
	output wire jalr_reg_file_rd_p0_req, // 读请求
	output wire[4:0] jalr_reg_file_rd_p0_addr, // 读地址
	input wire jalr_reg_file_rd_p0_grant, // 读许可
	input wire[31:0] jalr_reg_file_rd_p0_dout, // 读数据
	
	// 指令ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_inst_addr,
	output wire m_icb_cmd_inst_read, // const -> 1'b1
	output wire[31:0] m_icb_cmd_inst_wdata, // const -> 32'hxxxx_xxxx
	output wire[3:0] m_icb_cmd_inst_wmask, // const -> 4'b0000
	output wire m_icb_cmd_inst_valid,
	input wire m_icb_cmd_inst_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_inst_rdata,
	input wire m_icb_rsp_inst_err,
	input wire m_icb_rsp_inst_valid,
	output wire m_icb_rsp_inst_ready,
	
	// 取指结果
	output wire[127:0] m_if_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[3:0] m_if_res_msg, // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	output wire[inst_id_width-1:0] m_if_res_id, // 指令编号
	output wire m_if_res_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	output wire m_if_res_valid,
	input wire m_if_res_ready,
	
	// 指令总线访问超时标志
	output wire ibus_timeout,
	
	// 数据相关性跟踪
	// 是否有滞外的指令存储器访问请求
	output wire has_processing_imem_access_req,
	// 指令数据相关性跟踪表满标志
	input wire dpc_trace_tb_full,
	// 指令进入取指队列
	output wire[31:0] dpc_trace_enter_ifq_inst, // 取到的指令
	output wire[4:0] dpc_trace_enter_ifq_rd_id, // RD索引
	output wire dpc_trace_enter_ifq_rd_vld, // 是否需要写RD
	output wire dpc_trace_enter_ifq_is_long_inst, // 是否长指令
	output wire[inst_id_width-1:0] dpc_trace_enter_ifq_inst_id, // 指令编号
	output wire dpc_trace_enter_ifq_valid
);
	
	/** 内部配置 **/
	// 指令总线控制单元配置
	localparam pc_unaligned_imdt_resp = "false"; // 是否允许PC地址非对齐时立即响应
	
	/** 指令总线控制单元 **/
	// 指令存储器访问请求
	wire[31:0] imem_access_req_addr;
	wire imem_access_req_read;
	wire[31:0] imem_access_req_wdata;
	wire[3:0] imem_access_req_wmask;
	wire imem_access_req_valid;
	wire imem_access_req_ready;
	// 指令存储器访问应答
	wire[31:0] imem_access_resp_rdata;
	wire[1:0] imem_access_resp_err; // 错误类型(2'b00 -> 正常, 2'b01 -> 指令地址非对齐, 
								    //          2'b10 -> 指令总线访问错误, 2'b11 -> 响应超时)
	wire imem_access_resp_valid;
	
	panda_risc_v_ibus_ctrler #(
		.imem_access_timeout_th(imem_access_timeout_th),
		.inst_addr_alignment_width(inst_addr_alignment_width),
		.pc_unaligned_imdt_resp(pc_unaligned_imdt_resp),
		.en_extra_resp_latency("false"),
		.simulation_delay(simulation_delay)
	)panda_risc_v_ibus_ctrler_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.imem_access_req_addr(imem_access_req_addr),
		.imem_access_req_read(imem_access_req_read),
		.imem_access_req_wdata(imem_access_req_wdata),
		.imem_access_req_wmask(imem_access_req_wmask),
		.imem_access_req_valid(imem_access_req_valid),
		.imem_access_req_ready(imem_access_req_ready),
		
		.imem_access_resp_rdata(imem_access_resp_rdata),
		.imem_access_resp_err(imem_access_resp_err),
		.imem_access_resp_valid(imem_access_resp_valid),
		
		.m_icb_cmd_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_read(m_icb_cmd_inst_read),
		.m_icb_cmd_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_err(m_icb_rsp_inst_err),
		.m_icb_rsp_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_ready(m_icb_rsp_inst_ready),
		
		.ibus_timeout(ibus_timeout)
	);
	
	/** 预译码单元 **/
	// 当前的指令
	wire[31:0] now_inst;
	// 预译码信息
	wire is_b_inst; // 是否B指令
	wire is_jal_inst; // 是否JAL指令
	wire is_jalr_inst; // 是否JALR指令
	wire[20:0] jump_ofs_imm; // 跳转偏移量立即数
	wire illegal_inst; // 非法指令(标志)
	// 打包的预译码信息
	wire[63:0] pre_decoding_msg_packeted;
	
	panda_risc_v_pre_decoder panda_risc_v_pre_decoder_u(
		.inst(now_inst),
		
		.is_b_inst(is_b_inst),
		.is_jal_inst(is_jal_inst),
		.is_jalr_inst(is_jalr_inst),
		.is_csr_rw_inst(),
		.is_load_inst(),
		.is_store_inst(),
		.is_mul_inst(),
		.is_div_inst(),
		.is_rem_inst(),
		.is_ecall_inst(),
		.is_mret_inst(),
		.is_fence_inst(),
		.is_fence_i_inst(),
		.is_ebreak_inst(),
		.is_dret_inst(),
		.jump_ofs_imm(jump_ofs_imm),
		.rs1_vld(),
		.rs2_vld(),
		.rd_vld(),
		.csr_addr(),
		.rs1_id(rs1_id),
		.illegal_inst(illegal_inst),
		
		.pre_decoding_msg_packeted(pre_decoding_msg_packeted)
	);
	
	/** 指令存储器访问控制 **/
	wire to_rst; // 当前正在复位
	wire to_flush; // 当前正在冲刷
	wire[31:0] flush_addr_hold; // 保持的冲刷地址
	wire[31:0] now_pc; // 当前的PC
	wire[31:0] new_pc; // 新的PC
	wire to_jump; // 是否预测跳转
	wire[31:0] rs1_v; // RS1读结果
	wire vld_inst_gotten; // 获取到有效的指令(指示)
	wire jalr_baseaddr_vld; // JALR指令基址读完成(指示)
	wire[31:0] jalr_baseaddr_v; // 基址读结果
	
	panda_risc_v_imem_access_ctrler #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_imem_access_ctrler_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.rst_req(sys_reset_req),
		.flush_req(flush_req),
		.flush_addr(flush_addr),
		.rst_ack(rst_ack),
		.flush_ack(flush_ack),
		
		.to_rst(to_rst),
		.to_flush(to_flush),
		.flush_addr_hold(flush_addr_hold),
		.now_pc(now_pc),
		.new_pc(new_pc),
		.to_jump(to_jump),
		.rs1_v(rs1_v),
		
		.now_inst(now_inst),
		.is_jalr_inst(is_jalr_inst),
		.illegal_inst(illegal_inst),
		.pre_decoding_msg_packeted(pre_decoding_msg_packeted),
		
		.vld_inst_gotten(vld_inst_gotten),
		.jalr_baseaddr_vld(jalr_baseaddr_vld),
		.jalr_baseaddr_v(jalr_baseaddr_v),
		
		.imem_access_req_addr(imem_access_req_addr),
		.imem_access_req_read(imem_access_req_read),
		.imem_access_req_wdata(imem_access_req_wdata),
		.imem_access_req_wmask(imem_access_req_wmask),
		.imem_access_req_valid(imem_access_req_valid),
		.imem_access_req_ready(imem_access_req_ready),
		
		.imem_access_resp_rdata(imem_access_resp_rdata),
		.imem_access_resp_err(imem_access_resp_err),
		.imem_access_resp_valid(imem_access_resp_valid),
		
		.if_res_data(m_if_res_data),
		.if_res_msg(m_if_res_msg),
		.m_if_res_id(m_if_res_id),
		.m_if_res_is_first_inst_after_rst(m_if_res_is_first_inst_after_rst),
		.if_res_valid(m_if_res_valid),
		.if_res_ready(m_if_res_ready),
		
		.has_processing_imem_access_req(has_processing_imem_access_req),
		.dpc_trace_tb_full(dpc_trace_tb_full),
		.dpc_trace_enter_ifq_inst(dpc_trace_enter_ifq_inst),
		.dpc_trace_enter_ifq_rd_id(dpc_trace_enter_ifq_rd_id),
		.dpc_trace_enter_ifq_rd_vld(dpc_trace_enter_ifq_rd_vld),
		.dpc_trace_enter_ifq_is_long_inst(dpc_trace_enter_ifq_is_long_inst),
		.dpc_trace_enter_ifq_inst_id(dpc_trace_enter_ifq_inst_id),
		.dpc_trace_enter_ifq_valid(dpc_trace_enter_ifq_valid)
	);
	
	/** 下一PC生成 **/
	panda_risc_v_pc_gen panda_risc_v_pc_gen_u(
		.now_pc(now_pc),
		.rst_pc(rst_pc),
		
		.to_rst(to_rst),
		.to_flush(to_flush),
		.flush_addr_hold(flush_addr_hold),
		
		.rs1_v(rs1_v),
		
		.inst_len_type(1'b1), // 指令长度类型(1'b0 -> 16位, 1'b1 -> 32位)
		.is_b_inst(is_b_inst),
		.is_jal_inst(is_jal_inst),
		.is_jalr_inst(is_jalr_inst),
		.jump_ofs_imm(jump_ofs_imm),
		
		.to_jump(to_jump),
		
		.new_pc(new_pc)
	);
	
	/** 读JALR指令基址 **/
	panda_risc_v_jalr_baseaddr_rd #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_jalr_baseaddr_rd_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.to_rst(to_rst),
		.to_flush(to_flush),
		
		.rs1_raw_dpc(rs1_raw_dpc),
		
		.rs1_id(rs1_id),
		
		.jalr_x1_v(jalr_x1_v),
		.jalr_reg_file_rd_p0_req(jalr_reg_file_rd_p0_req),
		.jalr_reg_file_rd_p0_addr(jalr_reg_file_rd_p0_addr),
		.jalr_reg_file_rd_p0_grant(jalr_reg_file_rd_p0_grant),
		.jalr_reg_file_rd_p0_dout(jalr_reg_file_rd_p0_dout),
		
		.vld_inst_gotten(vld_inst_gotten),
		.is_jalr_inst(is_jalr_inst),
		.jalr_baseaddr_vld(jalr_baseaddr_vld),
		.jalr_baseaddr_v(jalr_baseaddr_v)
	);
	
endmodule
