`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:APB时钟转换模块 **/
class ApbClkCvtEnv #(
	real out_drive_t = 1 // 输出驱动延迟量
)extends uvm_env;
	
	// 组件
	local APBMasterAgent #(.out_drive_t(out_drive_t), .addr_width(32), .data_width(32)) m_apb_agt; // APB主机代理
	local APBSlaveAgent #(.out_drive_t(out_drive_t), .addr_width(32), .data_width(32)) s_apb_agt; // APB从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(APBTrans #(.addr_width(32), .data_width(32))) m_apb_trans_port;
	local uvm_blocking_get_port #(APBTrans #(.addr_width(32), .data_width(32))) s_apb_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(APBTrans #(.addr_width(32), .data_width(32))) m_apb_agt_fifo;
	local uvm_tlm_analysis_fifo #(APBTrans #(.addr_width(32), .data_width(32))) s_apb_agt_fifo;
	
	// 事务
	local APBTrans #(.addr_width(32), .data_width(32)) m_apb_trans;
	local APBTrans #(.addr_width(32), .data_width(32)) s_apb_trans;
	
	// 注册component
	`uvm_component_param_utils(ApbClkCvtEnv #(.out_drive_t(out_drive_t)))
	
	function new(string name = "ApbClkCvtEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_apb_agt = APBMasterAgent #(.out_drive_t(out_drive_t), .addr_width(32), .data_width(32))::
			type_id::create("agt1", this);
		this.m_apb_agt.is_active = UVM_ACTIVE;
		this.s_apb_agt = APBSlaveAgent #(.out_drive_t(out_drive_t), .addr_width(32), .data_width(32))::
			type_id::create("agt2", this);
		this.s_apb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_apb_trans_port = new("m_apb_trans_port", this);
		this.s_apb_trans_port = new("s_apb_trans_port", this);
		
		// 创建通信fifo
		this.m_apb_agt_fifo = new("m_apb_agt_fifo", this);
		this.s_apb_agt_fifo = new("s_apb_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_apb_agt.apb_analysis_port.connect(this.m_apb_agt_fifo.analysis_export);
		this.m_apb_trans_port.connect(this.m_apb_agt_fifo.blocking_get_export);
		this.s_apb_agt.apb_analysis_port.connect(this.s_apb_agt_fifo.analysis_export);
		this.s_apb_trans_port.connect(this.s_apb_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_apb_trans_port.get(this.m_apb_trans);
				// this.m_apb_trans.print(); // 打印事务
			end
			forever
			begin
				this.s_apb_trans_port.get(this.s_apb_trans);
				// this.s_apb_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
