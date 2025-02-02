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

`ifndef __DRIVER_H

`define __DRIVER_H

`include "transactions.sv"

// `define BlkCtrlDriver
`define AXIDriver
// `define APBDriver
// `define AXISDriver

/** 驱动器:块级控制主机 **/
`ifdef BlkCtrlDriver
class BlkCtrlMasterDriver #(
	real out_drive_t = 1 // 输出驱动延迟量
)extends uvm_driver #(BlkCtrlTrans);
	
	local virtual BlkCtrl #(.out_drive_t(out_drive_t)).master blk_ctrl_if; // 块级控制虚接口
	
	// 注册component
	`uvm_component_param_utils(BlkCtrlMasterDriver #(.out_drive_t(out_drive_t)))
	
	function new(string name = "BlkCtrlMasterDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual BlkCtrl #(.out_drive_t(out_drive_t)).master)::get(this, "", "blk_ctrl_if", this.blk_ctrl_if))
		begin
			`uvm_fatal("BlkCtrlMasterDriver", "virtual interface must be set for blk_ctrl_if!!!")
		end
		
		`uvm_info("BlkCtrlMasterDriver", "BlkCtrlMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		// 初始化块级控制接口
		this.blk_ctrl_if.cb_master.start <= 1'b0;
		this.blk_ctrl_if.cb_master.to_continue <= 1'b1;
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref BlkCtrlTrans tr);
		// 等待启动功能模块
		repeat(tr.start_wait_period_n)
			@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		
		this.blk_ctrl_if.cb_master.start <= 1'b1;
		
		@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		
		this.blk_ctrl_if.cb_master.start <= 1'b0;
		
		// 等待功能模块完成
		do
		begin
			@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		end
		while(!this.blk_ctrl_if.done);
	endtask
	
endclass
`endif

/** 驱动器:AXI主机 **/
`ifdef AXIDriver
class AXIMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_driver #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
	.bresp_width(bresp_width), .rresp_width(rresp_width)));
	
	local virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)).master axi_if; // AXI虚接口
	
	// 事务fifo
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_ar_trans_fifo[$];
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_aw_trans_fifo[$];
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_w_trans_fifo[$];
	
	// 配置
	local int unsigned max_trans_buffer_n = 12; // 最大的事务缓存深度
	
	// 注册component
	`uvm_component_param_utils_begin(AXIMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
		`uvm_field_int(max_trans_buffer_n, UVM_ALL_ON)
	`uvm_component_utils_end
	
	function new(string name = "AXIMasterDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)).master)::get(this, "", "axi_if", this.axi_if))
		begin
			`uvm_fatal("AXIMasterDriver", "virtual interface must be set for axi_if!!!")
		end
		
		`uvm_info("AXIMasterDriver", 
			$sformatf("AXIMasterDriver built(max_trans_buffer_n = %d)!", this.max_trans_buffer_n), UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			drive_ar();
			drive_r();
			drive_aw();
			drive_w();
			drive_b();
			
			forever
			begin
				wait((this.axi_ar_trans_fifo.size() < this.max_trans_buffer_n) && 
					(this.axi_aw_trans_fifo.size() < this.max_trans_buffer_n));
				
				this.seq_item_port.get_next_item(this.req); // 获取下一事务
				// this.req.print();
				
				if(this.req.is_rd_trans)
				begin
					this.axi_ar_trans_fifo.push_back(this.req);
				end
				else
				begin
					this.axi_aw_trans_fifo.push_back(this.req);
					this.axi_w_trans_fifo.push_back(this.req);
				end
				
				this.seq_item_port.item_done(); // 发送信号:本事务已完成
			end
		join_none
	endtask
	
	local task drive_ar();
		// 初始化AXI总线的AR通道
		this.axi_if.cb_master.araddr <= {addr_width{1'bx}};
		this.axi_if.cb_master.arburst <= 2'bxx;
		this.axi_if.cb_master.arcache <= 4'bxxxx;
		this.axi_if.cb_master.arlen <= 8'dx;
		this.axi_if.cb_master.arlock <= 1'bx;
		this.axi_if.cb_master.arprot <= 3'bxxx;
		this.axi_if.cb_master.arsize <= 3'bxxx;
		this.axi_if.cb_master.arvalid <= 1'b0;
		
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
			
			wait(this.axi_ar_trans_fifo.size() > 0);
			
			axi_trans = this.axi_ar_trans_fifo.pop_front();
			
			// 等待AR通道有效
			repeat(axi_trans.addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// 给出有效数据
			this.axi_if.cb_master.araddr <= axi_trans.addr;
			this.axi_if.cb_master.arburst <= axi_trans.burst;
			this.axi_if.cb_master.arcache <= axi_trans.cache;
			this.axi_if.cb_master.arlen <= axi_trans.len;
			this.axi_if.cb_master.arlock <= axi_trans.lock;
			this.axi_if.cb_master.arprot <= axi_trans.prot;
			this.axi_if.cb_master.arsize <= axi_trans.size;
			this.axi_if.cb_master.arvalid <= 1'b1;
			
			// 等待AR通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.arvalid && this.axi_if.arready));
			
			// 将AXI总线的AR通道恢复到无效状态
			this.axi_if.cb_master.araddr <= {addr_width{1'bx}};
			this.axi_if.cb_master.arburst <= 2'bxx;
			this.axi_if.cb_master.arcache <= 4'bxxxx;
			this.axi_if.cb_master.arlen <= 8'dx;
			this.axi_if.cb_master.arlock <= 1'bx;
			this.axi_if.cb_master.arprot <= 3'bxxx;
			this.axi_if.cb_master.arsize <= 3'bxxx;
			this.axi_if.cb_master.arvalid <= 1'b0;
		end
	endtask
	
	local task drive_r();
		// 初始化AXI总线的R通道
		this.axi_if.cb_master.rready <= 1'b0;
		
		forever
		begin
			automatic byte unsigned r_wait_period_n = $urandom_range(0, 2);
			
			// 等待R通道就绪
			repeat(r_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// R通道就绪
			this.axi_if.cb_master.rready <= 1'b1;
			
			// 等待R通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.rvalid && this.axi_if.rready));
			
			// 将AXI总线的R通道恢复到无效状态
			this.axi_if.cb_master.rready <= 1'b0;
		end
	endtask
	
	local task drive_aw();
		// 初始化AXI总线的AW通道
		this.axi_if.cb_master.awaddr <= {addr_width{1'bx}};
		this.axi_if.cb_master.awburst <= 2'bxx;
		this.axi_if.cb_master.awcache <= 4'bxxxx;
		this.axi_if.cb_master.awlen <= 8'dx;
		this.axi_if.cb_master.awlock <= 1'bx;
		this.axi_if.cb_master.awprot <= 3'bxxx;
		this.axi_if.cb_master.awsize <= 3'bxxx;
		this.axi_if.cb_master.awvalid <= 1'b0;
		
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
			
			wait(this.axi_aw_trans_fifo.size() > 0);
			
			axi_trans = this.axi_aw_trans_fifo.pop_front();
			
			// 等待AR通道有效
			repeat(axi_trans.addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// 给出有效数据
			this.axi_if.cb_master.awaddr <= axi_trans.addr;
			this.axi_if.cb_master.awburst <= axi_trans.burst;
			this.axi_if.cb_master.awcache <= axi_trans.cache;
			this.axi_if.cb_master.awlen <= axi_trans.len;
			this.axi_if.cb_master.awlock <= axi_trans.lock;
			this.axi_if.cb_master.awprot <= axi_trans.prot;
			this.axi_if.cb_master.awsize <= axi_trans.size;
			this.axi_if.cb_master.awvalid <= 1'b1;
			
			// 等待AW通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.awvalid && this.axi_if.awready));
			
			// 将AXI总线的AW通道恢复到无效状态
			this.axi_if.cb_master.awaddr <= {addr_width{1'bx}};
			this.axi_if.cb_master.awburst <= 2'bxx;
			this.axi_if.cb_master.awcache <= 4'bxxxx;
			this.axi_if.cb_master.awlen <= 8'dx;
			this.axi_if.cb_master.awlock <= 1'bx;
			this.axi_if.cb_master.awprot <= 3'bxxx;
			this.axi_if.cb_master.awsize <= 3'bxxx;
			this.axi_if.cb_master.awvalid <= 1'b0;
		end
	endtask
	
	local task drive_w();
		// 初始化AXI总线的W通道
		this.axi_if.cb_master.wdata <= {data_width{1'bx}};
		this.axi_if.cb_master.wlast <= 1'bx;
		this.axi_if.cb_master.wstrb <= {(data_width/8){1'bx}};
		this.axi_if.cb_master.wvalid <= 1'b0;
		
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
			
			wait(this.axi_w_trans_fifo.size() > 0);
			
			axi_trans = this.axi_w_trans_fifo.pop_front();
			
			for(int i = 0;i < axi_trans.data_n;i++)
			begin
				// 等待W通道有效
				repeat(axi_trans.wdata_wait_period_n[i])
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				
				// 给出有效数据
				this.axi_if.cb_master.wdata <= axi_trans.wdata[i];
				this.axi_if.cb_master.wlast <= axi_trans.wlast[i];
				this.axi_if.cb_master.wstrb <= axi_trans.wstrb[i];
				this.axi_if.cb_master.wvalid <= 1'b1;
				
				// 等待AW通道握手完成
				do
				begin
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				end
				while(!(this.axi_if.wvalid && this.axi_if.wready));
				
				// 将AXI总线的W通道恢复到无效状态
				this.axi_if.cb_master.wdata <= {data_width{1'bx}};
				this.axi_if.cb_master.wlast <= 1'bx;
				this.axi_if.cb_master.wstrb <= {(data_width/8){1'bx}};
				this.axi_if.cb_master.wvalid <= 1'b0;
			end
		end
	endtask
	
	local task drive_b();
		// 初始化AXI总线的B通道
		this.axi_if.cb_master.bready <= 1'b0;
		
		forever
		begin
			automatic byte unsigned b_wait_period_n = $urandom_range(0, 15);
			
			// 等待R通道就绪
			repeat(b_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// B通道就绪
			this.axi_if.cb_master.bready <= 1'b1;
			
			// 等待R通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.bvalid && this.axi_if.bready));
			
			// 将AXI总线的B通道恢复到无效状态
			this.axi_if.cb_master.bready <= 1'b0;
		end
	endtask
	
endclass
`endif

/** 驱动器:AXI从机 **/
`ifdef AXIDriver
class AXISlaveDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_driver #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
	.bresp_width(bresp_width), .rresp_width(rresp_width)));
	
	local virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)).slave axi_if; // AXI虚接口
	
	local int unsigned rd_trans_to_resp_n; // 可响应的读事务个数
	local int unsigned wt_trans_to_resp_n_at_aw; // 可响应的写事务个数(保证AW在先)
	local int unsigned wt_trans_to_resp_n_at_w; // 可响应的写事务个数(保证W在先)
	
	// 注册component
	`uvm_component_param_utils(AXISlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
	
	function new(string name = "AXISlaveDriver", uvm_component parent = null);
		super.new(name, parent);
		
		this.rd_trans_to_resp_n = 0;
		this.wt_trans_to_resp_n_at_aw = 0;
		this.wt_trans_to_resp_n_at_w = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)).slave)::get(this, "", "axi_if", this.axi_if))
		begin
			`uvm_fatal("AXISlaveDriver", "virtual interface must be set for axi_if!!!")
		end
		
		`uvm_info("AXISlaveDriver", "AXISlaveDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		// 初始化AXI总线
		this.axi_if.cb_slave.arready <= 1'b0;
		this.axi_if.cb_slave.awready <= 1'b0;
		this.axi_if.cb_slave.bresp <= {bresp_width{1'bx}};
		this.axi_if.cb_slave.bvalid <= 1'b0;
		this.axi_if.cb_slave.rdata <= {data_width{1'bx}};
		this.axi_if.cb_slave.rlast <= 1'bx;
		this.axi_if.cb_slave.rresp <= {rresp_width{1'bx}};
		this.axi_if.cb_slave.rvalid <= 1'b0;
		this.axi_if.cb_slave.wready <= 1'b0;
		
		fork
			this.drive_ar_chn(); // 驱动AR通道
			this.drive_aw_chn(); // 驱动AW通道
			this.drive_r_chn(); // 驱动R通道
			this.drive_w_chn(); // 驱动W通道
			this.drive_b_chn(); // 驱动B通道
		join_none
	endtask
	
	local task drive_ar_chn();
		forever
		begin
			automatic byte unsigned addr_wait_period_n = $urandom_range(0, 25);
			
			repeat(addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.arready <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.arvalid && this.axi_if.arready));
			
			this.rd_trans_to_resp_n++;
			
			this.axi_if.cb_slave.arready <= 1'b0;
		end
	endtask
	
	local task drive_aw_chn();
		forever
		begin
			automatic byte unsigned addr_wait_period_n = $urandom_range(0, 25);
			
			repeat(addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.awready <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.awvalid && this.axi_if.awready));
			
			this.wt_trans_to_resp_n_at_aw++;
			
			this.axi_if.cb_slave.awready <= 1'b0;
		end
	endtask
	
	local task drive_w_chn();
		forever
		begin
			automatic byte unsigned wdata_wait_period_n = $urandom_range(0, 2);
			
			repeat(wdata_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.wready <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.wvalid && this.axi_if.wready));
			
			if(this.axi_if.wlast)
				this.wt_trans_to_resp_n_at_w++;
			
			this.axi_if.cb_slave.wready <= 1'b0;
		end
	endtask
	
	local task drive_b_chn();
		forever
		begin
			automatic byte unsigned bresp_wait_period_n = $urandom_range(0, 8);
			
			// 等待一个可响应的写事务
			wait((this.wt_trans_to_resp_n_at_aw > 0) && (this.wt_trans_to_resp_n_at_w > 0));
			this.wt_trans_to_resp_n_at_aw--;
			this.wt_trans_to_resp_n_at_w--;
			
			repeat(bresp_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.bresp <= 2'b00;
			this.axi_if.cb_slave.bvalid <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.bvalid && this.axi_if.bready));
			
			this.axi_if.cb_slave.bresp <= {bresp_width{1'bx}};
			this.axi_if.cb_slave.bvalid <= 1'b0;
		end
	endtask
	
	local task drive_r_chn();
		forever
		begin
			// 等待一个可响应的读事务
			wait(this.rd_trans_to_resp_n > 0);
			this.rd_trans_to_resp_n--;
			
			this.seq_item_port.get_next_item(this.req); // 获取下一个AXI读数据事务
			// this.req.print();
			
			for(int unsigned i = 0;i < this.req.rdata.size();i++)
			begin
				// 等待数据有效
				repeat(this.req.rdata_wait_period_n[i])
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				
				// 给出有效数据
				this.axi_if.cb_slave.rdata <= this.req.rdata[i];
				this.axi_if.cb_slave.rlast <= this.req.rlast[i];
				this.axi_if.cb_slave.rresp <= this.req.rresp[i];
				this.axi_if.cb_slave.rvalid <= 1'b1;
				
				// 等待握手完成
				do
				begin
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				end
				while(!(this.axi_if.rvalid && this.axi_if.rready));
				
				// 总线恢复到无效状态
				this.axi_if.cb_slave.rdata <= {data_width{1'bx}};
				this.axi_if.cb_slave.rlast <= 1'bx;
				this.axi_if.cb_slave.rresp <= {rresp_width{1'bx}};
				this.axi_if.cb_slave.rvalid <= 1'b0;
			end
			
			this.seq_item_port.item_done(); // 发送信号:本事务已完成
		end
	endtask
	
endclass
`endif

/** 驱动器:APB主机 **/
`ifdef APBDriver
class APBMasterDriver extends uvm_driver #(APBTrans);
	
	local virtual APB #(.out_drive_t(1), .addr_width(32), .data_width(32)).master apb_if; // APB虚接口
	
	// 注册component
	`uvm_component_utils(APBMasterDriver)
	
	function new(string name = "APBMasterDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual APB.master)::get(this, "", "apb_if", this.apb_if))
		begin
			`uvm_fatal("APBMasterDriver", "virtual interface must be set for apb_if!!!")
		end
		
		`uvm_info("APBMasterDriver", "APBMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
	
		// 初始化APB总线
		this.apb_if.cb_master.paddr <= 32'dx;
		this.apb_if.cb_master.pselx <= 1'b0;
		this.apb_if.cb_master.penable <= 1'b0;
		this.apb_if.cb_master.pwrite <= 1'bx;
		this.apb_if.cb_master.pwdata <= 32'dx;
		this.apb_if.cb_master.pstrb <= 4'dx;
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref APBTrans tr);
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
        
		// APB传输建立(setup)阶段
		this.apb_if.cb_master.paddr <= tr.addr;
		this.apb_if.cb_master.pselx <= 1'b1;
		this.apb_if.cb_master.penable <= 1'b0;
		this.apb_if.cb_master.pwrite <= tr.write;
		this.apb_if.cb_master.pwdata <= tr.write ? tr.wdata:32'dx;
		this.apb_if.cb_master.pstrb <= tr.write ? tr.wstrb:4'dx;
		
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// APB传输数据(data)阶段
		this.apb_if.cb_master.penable <= 1'b1;
		
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// 等待APB传输完成(pready有效)
		while(this.apb_if.pready == 1'b0)
			@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// APB传输完成
		this.apb_if.cb_master.paddr <= 32'dx;
		this.apb_if.cb_master.pselx <= 1'b0;
		this.apb_if.cb_master.penable <= 1'b0;
		this.apb_if.cb_master.pwrite <= 1'bx;
		this.apb_if.cb_master.pwdata <= 32'dx;
		this.apb_if.cb_master.pstrb <= 4'dx;
	endtask
	
endclass
`endif

/** 驱动器:AXIS主机 **/
`ifdef AXISDriver
class AXISMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_driver #(AXISTrans #(.data_width(data_width), .user_width(user_width)));
	
	local virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).master axis_if; // AXIS虚接口
	
	// 注册component
	`uvm_component_param_utils(AXISMasterDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISMasterDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).master)::
			get(this, "", "axis_if", this.axis_if))
		begin
			`uvm_fatal("AXISMasterDriver", "virtual interface must be set for axis_if!!!")
		end
		
		`uvm_info("AXISMasterDriver", "AXISMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.axis_if.cb_master.data <= {data_width{1'bx}};
		this.axis_if.cb_master.keep <= {(data_width/8){1'bx}};
		this.axis_if.cb_master.last <= 1'bx;
		// this.axis_if.cb_master.user <= {user_width{1'bx}};
		this.axis_if.cb_master.valid <= 1'b0;
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// `uvm_info("AXISMasterDriver", "AXISMasterDriver got transaction!", UVM_LOW)
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref AXISTrans #(.data_width(data_width), .user_width(user_width)) tr);
		for(int unsigned i = 0;i < tr.data_n;i++)
		begin
			// 等待数据有效
			repeat(tr.wait_period_n[i])
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			
			// 给出有效数据
			this.axis_if.cb_master.data <= tr.data[i];
			this.axis_if.cb_master.keep <= tr.keep[i];
			this.axis_if.cb_master.last <= tr.last[i];
			this.axis_if.cb_master.user <= tr.user[i];
			this.axis_if.cb_master.valid <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			end
			while(!(this.axis_if.valid && this.axis_if.ready));
			
			// 总线恢复到无效状态
			this.axis_if.cb_master.data <= {data_width{1'bx}};
			this.axis_if.cb_master.keep <= {(data_width/8){1'bx}};
			this.axis_if.cb_master.last <= 1'bx;
			// this.axis_if.cb_master.user <= {user_width{1'bx}};
			this.axis_if.cb_master.valid <= 1'b0;
		end
	endtask
	
endclass

/** 驱动器:AXIS从机 **/
class AXISSlaveDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_driver;
	
	local virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).slave axis_if; // AXIS虚接口
	
	// 注册component
	`uvm_component_param_utils(AXISSlaveDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISSlaveDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).slave)::
			get(this, "", "axis_if", this.axis_if))
		begin
			`uvm_fatal("AXISSlaveDriver", "virtual interface must be set for axis_if!!!")
		end
		
		`uvm_info("AXISSlaveDriver", "AXISSlaveDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.axis_if.cb_slave.ready <= 1'b0;
		
		forever
		begin
            // automatic int unsigned s_axis_wait_n = $urandom_range(0, 2);
			automatic int unsigned s_axis_wait_n = 0;
			
			repeat(s_axis_wait_n)
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			
			this.axis_if.cb_slave.ready <= 1'b1;
			
			// 等待AXIS握手
			do
			begin
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			end
			while(!(this.axis_if.valid & this.axis_if.ready));
			
			this.axis_if.cb_slave.ready <= 1'b0;
        end
	endtask
	
endclass
`endif

`endif
