module i2c_master #(
    parameter integer INPUT_CLK = 50_000_000, // System clock frequency in Hz (50 MHz)
    parameter integer BUS_CLK   = 100_000     // I2C bus clock frequency in Hz (100 kHz)
)(
    input  wire       clk,      // System clock
    input  wire       rst_n,    // Active-low asynchronous reset
    
    // User Control Interface
    input  wire       ena,      // Enable transaction
    input  wire [6:0] addr,     // 7-bit target slave address
    input  wire       rw,       // Read/Write: 0 = Write, 1 = Read
    input  wire [7:0] data_wr,  // Data to write to slave
    output reg  [7:0] data_rd,  // Data read from slave
    output reg        busy,     // Signals transaction in progress
    output reg        ack_error,// Acknowledge error flag (1 = no ACK received)
    
    // Physical I/O Lines (Open-Drain implementation)
    inout  wire       scl,
    inout  wire       sda
);

    // Clock divider calculation for SCL generation
    localparam integer DIVIDER = (INPUT_CLK / BUS_CLK) / 4;

    // FSM States
    localparam [3:0] 
        IDLE      = 4'd0,
        START     = 4'd1,
        COMMAND   = 4'd2,
        ACK_ADDR  = 4'd3,
        WR_DATA   = 4'd4,
        RD_DATA   = 4'd5,
        ACK_DATA  = 4'd6,
        STOP      = 4'd7;

    reg [3:0] state;
    reg [3:0] next_state;

    // Internal clock dividers & counters
    reg [31:0] clk_counter;
    reg        scl_clk;     // Internal clock tick for I2C state changes
    reg [2:0]  bit_cnt;     // Tracks 8 bits + ACK

    // Tri-state control signals (0 = drive low, 1 = release/float high)
    reg scl_oe, sda_oe;

    assign scl = (scl_oe) ? 1'b0 : 1'bz;
    assign sda = (sda_oe) ? 1'b0 : 1'bz;

    // Generate internal divided clock tick for SCL
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_counter <= 0;
            scl_clk     <= 0;
        end else if (clk_counter == DIVIDER - 1) begin
            clk_counter <= 0;
            scl_clk     <= ~scl_clk;
        end else begin
            clk_counter <= clk_counter + 1;
        end
    end

    // State Machine Registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= IDLE;
        else 
            state <= next_state;
    end

    // Shift registers for data transmission/reception
    reg [7:0] addr_rw_reg;
    reg [7:0] data_wr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            ack_error <= 1'b0;
            data_rd   <= 8'h00;
            bit_cnt   <= 3'd7;
            scl_oe    <= 1'b1; // Release line logic handled via FSM
            sda_oe    <= 1'b1;
            addr_rw_reg <= 8'h00;
            data_wr_reg <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    busy      <= 1'b0;
                    scl_oe    <= 1'b1; // High (released)
                    sda_oe    <= 1'b1; // High (released)
                    if (ena) begin
                        busy        <= 1'b1;
                        addr_rw_reg <= {addr, rw};
                        data_wr_reg <= data_wr;
                        ack_error   <= 1'b0;
                    end
                end

                START: begin
                    sda_oe <= 1'b1; // Pull SDA low while SCL is high
                    scl_oe <= 1'b1; 
                end

                COMMAND: begin
                    // Transmit Address + R/W bit sequentially
                    scl_oe <= 1'b0; // SCL low
                    sda_oe <= ~addr_rw_reg[bit_cnt];
                end

                ACK_ADDR: begin
                    sda_oe <= 1'b1; // Release SDA to listen for ACK
                    if (scl_clk) begin
                        ack_error <= sda; // Sample ACK from slave
                    end
                end

                WR_DATA: begin
                    scl_oe <= 1'b0;
                    sda_oe <= ~data_wr_reg[bit_cnt];
                end

                RD_DATA: begin
                    sda_oe <= 1'b1; // Release SDA for reading
                    if (scl_clk) begin
                        data_rd <= {data_rd[6:0], sda};
                    end
                end

                ACK_DATA: begin
                    // Master sends ACK/NACK (here sending NACK/ACK logic placeholder)
                    sda_oe <= 1'b1; 
                end

                STOP: begin
                    sda_oe <= 1'b0; // Bring SDA low, then SCL high, then SDA high
                    scl_oe <= 1'b1;
                end
            endcase
        end
    end

    // Next State Logic
    always @* begin
        next_state = state;
        case (state)
            IDLE:      if (ena) next_state = START;
            START:     if (scl_clk) next_state = COMMAND;
            COMMAND:   if (bit_cnt == 0 && scl_clk) next_state = ACK_ADDR;
            ACK_ADDR:  if (scl_clk) next_state = (rw) ? RD_DATA : WR_DATA;
            WR_DATA:   if (bit_cnt == 0 && scl_clk) next_state = ACK_DATA;
            RD_DATA:   if (bit_cnt == 0 && scl_clk) next_state = ACK_DATA;
            ACK_DATA:  if (scl_clk) next_state = STOP;
            STOP:      if (scl_clk) next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end

endmodule