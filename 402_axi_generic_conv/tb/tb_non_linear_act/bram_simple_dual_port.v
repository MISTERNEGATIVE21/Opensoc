`timescale 1ns / 1ps
/********************************************************************
本模块: 简单双端口Bram

描述: 
可选读延迟1clk或2clk

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2022/1/11
********************************************************************/


module bram_simple_dual_port #(
    parameter style = "HIGH_PERFORMANCE", // 存储器样式(HIGH_PERFORMANCE|LOW_LATENCY)
    parameter integer mem_width = 32, // 存储器位宽
    parameter integer mem_depth = 4096, // 存储器深度
    parameter INIT_FILE = "no_init", // 初始化文件路径
    parameter byte_write_mode = "false", // 是否使用写字节掩码
    parameter integer simulation_delay = 1 // 仿真延时
)
(
    // clk
    input wire clk,
    
    // mem write
    input wire[((byte_write_mode == "true") ? mem_width/8:1)-1:0] wen_a,
    input wire[clogb2(mem_depth-1):0] addr_a,
    input wire[mem_width-1:0] din_a,
    
    // mem read
    input wire ren_b,
    input wire[clogb2(mem_depth-1):0] addr_b,
    output wire[mem_width-1:0] dout_b
);

    // 计算bit_depth的最高有效位编号(即位数-1)             
    function integer clogb2 (input integer bit_depth);              
    begin                                                           
        for(clogb2=-1; bit_depth>0; clogb2=clogb2+1)                   
          bit_depth = bit_depth >> 1;                                 
        end                                        
    endfunction
    
    (* ram_style="block" *) reg[mem_width-1:0] mem[mem_depth-1:0]; // 存储器
    reg[mem_width-1:0] ram_data_b;
    
    generate
        if (INIT_FILE != "")
        begin
            if(INIT_FILE == "default")
            begin
                integer ram_index;
                initial
                for (ram_index = 0; ram_index < mem_depth; ram_index = ram_index + 1)
                    mem[ram_index] = ram_index;
            end
            else if(INIT_FILE != "no_init")
            begin
                initial
                    $readmemh(INIT_FILE, mem, 0, mem_depth - 1);
            end
        end
        else
        begin
            integer ram_index;
            initial
            for (ram_index = 0; ram_index < mem_depth; ram_index = ram_index + 1)
                mem[ram_index] = {mem_width{1'b0}};
        end
    endgenerate
    
    // 读写控制逻辑
    genvar byte_write_i;
    generate
        if(byte_write_mode == "true")
        begin
            for(byte_write_i = 0;byte_write_i < mem_width/8;byte_write_i = byte_write_i + 1)
            begin
                always @(posedge clk)
                begin
                    if(wen_a[byte_write_i])
                        mem[addr_a][(byte_write_i+1)*8-1:byte_write_i*8] <= # simulation_delay din_a[(byte_write_i+1)*8-1:byte_write_i*8];
                end
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(wen_a)
                    mem[addr_a] <= # simulation_delay din_a;
            end
        end
    endgenerate
    
    always @(posedge clk)
    begin
        if(ren_b)
            ram_data_b <= # simulation_delay mem[addr_b];
    end
    
    generate
        if(style == "HIGH_PERFORMANCE")
        begin
            // 使用输出寄存器
            reg[mem_width-1:0] data_b;
            
            assign dout_b = data_b;
            
            always @(posedge clk)
                data_b <= #simulation_delay ram_data_b;
        end
        else
        begin
            // 不使用输出寄存器
            assign dout_b = ram_data_b;
        end
    endgenerate
    
endmodule
