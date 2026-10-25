`timescale 1ns / 1ps

module tb_i2c_master();

    parameter INPUT_CLK = 50_000_000;
    parameter BUS_CLK   = 400_000; // Accelerated for quick simulation

    reg       clk;
    reg       rst_n;
    reg       ena;
    reg [6:0] addr;
    reg       rw;
    reg [7:0] data_wr;
    wire [7:0] data_rd;
    wire      busy;
    wire      ack_error;
    
    wire      scl;
    wire      sda;

    // Pull-up resistors emulation for open-drain lines
    pullup(scl);
    pullup(sda);

    // Instantiate Unit Under Test (UUT)
    i2c_master #(
        .INPUT_CLK(INPUT_CLK),
        .BUS_CLK(BUS_CLK)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .addr(addr),
        .rw(rw),
        .data_wr(data_wr),
        .data_rd(data_rd),
        .busy(busy),
        .ack_error(ack_error),
        .scl(scl),
        .sda(sda)
    );

    // Generate 50 MHz Clock
    always #10 clk = ~clk;

    initial begin
        // Initialize signals
        clk     = 0;
        rst_n   = 0;
        ena     = 0;
        addr    = 7'h50; // Example EEPROM Address
        rw      = 1'b0;  // Write operation
        data_wr = 8'hA5; // Data pattern

        #100;
        rst_n = 1; // Release reset
        
        #200;
        // Trigger a write transaction
        @(posedge clk);
        ena = 1;
        @(posedge clk);
        ena = 0;

        // Wait for transaction completion
        @(negedge busy);
        
        #1000;
        $finish;
    end

    initial begin
        $dumpfile("i2c_master_tb.vcd");
        $dumpvars(0, tb_i2c_master);
    end

endmodule