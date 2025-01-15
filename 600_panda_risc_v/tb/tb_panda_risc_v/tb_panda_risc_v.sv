`timescale 1ns / 1ps

module tb_panda_risc_v();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer IMEM_DEPTH = 8 * 1024; // 指令存储器深度
	localparam integer DMEM_DEPTH = 8 * 1024; // 数据存储器深度
	localparam IMEM_INIT_FILE = "E:/modelsim/tb_panda_risc_v/inst_test/rv32um-p-remu.txt"; // 指令存储器的初始化文件路径
	localparam DMEM_INIT_FILE = "E:/modelsim/tb_panda_risc_v/inst_test/rv32um-p-remu.txt"; // 数据存储器的初始化文件路径
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
	
	/** 汇编程序测试 **/
	wire[31:0] x3;
	wire[31:0] x26;
	wire[31:0] x27;
	
	assign x3 = panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[3];
	assign x26 = panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[26];
	assign x27 = panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[27];
	
	initial
	begin
		$display("test running...");
		
		wait(x26 == 32'b1);
		
        # (clk_p * 10);
		
        if(x27 == 32'b1)
		begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
            $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end
		else
		begin
		    $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
			
            $display("fail testnum = %2d", x3);
			
            for(int i = 0;i < 32;i++)
			begin
				$display("x%2d = 0x%x", i, 
					panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[i]);
			end
        end
	end
	
	/** 待测模块 **/
	panda_risc_v_sim #(
		.IMEM_DEPTH(IMEM_DEPTH),
		.DMEM_DEPTH(DMEM_DEPTH),
		.IMEM_INIT_FILE(IMEM_INIT_FILE),
		.DMEM_INIT_FILE(DMEM_INIT_FILE),
		.simulation_delay(simulation_delay)
	)panda_risc_v_sim_u(
		.clk(clk),
		.ext_resetn(rst_n),
		
		.sw_reset(1'b0),
		
		.ibus_timeout(),
		.dbus_timeout(),
		
		.sw_itr_req(1'b0),
		.tmr_itr_req(1'b0),
		.ext_itr_req(1'b0)
	);
	
endmodule
