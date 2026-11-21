// Simple behavioral SPI slave: mirrors the same CPOL/CPHA edge convention
// as the master under test. Used purely as a loopback partner in simulation
// so the testbench can check real data integrity in both directions.
module spi_slave_model #(
    parameter MAX_WIDTH = 16
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 sck,
    input  wire                 cs,       // active low
    input  wire                 mosi,
    output reg                  miso,
    input  wire                 cpol,
    input  wire                 cpha,
    input  wire [4:0]           word_len,
    input  wire [MAX_WIDTH-1:0] tx_data,  // what the slave will send back, latched at cs-fall
    output reg  [MAX_WIDTH-1:0] rx_data,  // what the slave received, latched at cs-rise
    output reg                  done      // one-cycle pulse when a transfer completes (cs rises)
);
    reg sck_prev, cs_prev;
    reg [MAX_WIDTH-1:0] tx_shift;
    reg [MAX_WIDTH-1:0] rx_shift;
    reg [4:0] bit_count;
    reg active;

    wire sck_rising  = (sck == 1'b1 && sck_prev == 1'b0);
    wire sck_falling = (sck == 1'b0 && sck_prev == 1'b1);
    wire cs_falling  = (cs  == 1'b0 && cs_prev  == 1'b1);
    wire cs_rising   = (cs  == 1'b1 && cs_prev  == 1'b0);

    wire sample_edge = (cpha == 1'b0) ? ((cpol == 1'b0) ? sck_rising  : sck_falling) :
                                         ((cpol == 1'b0) ? sck_falling : sck_rising);
    wire shift_edge  = (cpha == 1'b0) ? ((cpol == 1'b0) ? sck_falling : sck_rising) :
                                         ((cpol == 1'b0) ? sck_rising  : sck_falling);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sck_prev  <= 1'b0;
            cs_prev   <= 1'b1;
            miso      <= 1'b0;
            rx_data   <= {MAX_WIDTH{1'b0}};
            rx_shift  <= {MAX_WIDTH{1'b0}};
            tx_shift  <= {MAX_WIDTH{1'b0}};
            bit_count <= 5'b0;
            active    <= 1'b0;
            done      <= 1'b0;
        end else begin
            sck_prev <= sck;
            cs_prev  <= cs;
            done     <= 1'b0;

            if (cs_falling) begin
                active    <= 1'b1;
                bit_count <= 5'b0;
                rx_shift  <= {MAX_WIDTH{1'b0}};
                tx_shift  <= tx_data << (MAX_WIDTH - word_len);
                if (cpha == 1'b0) begin
                    miso     <= tx_data[word_len-1];
                    tx_shift <= (tx_data << (MAX_WIDTH - word_len)) << 1;
                end else begin
                    miso <= 1'b0;
                end
            end

            if (active && sample_edge) begin
                rx_shift  <= {rx_shift[MAX_WIDTH-2:0], mosi};
                bit_count <= bit_count + 1'b1;
            end

            if (active && shift_edge) begin
                if (bit_count != word_len) begin
                    miso     <= tx_shift[MAX_WIDTH-1];
                    tx_shift <= {tx_shift[MAX_WIDTH-2:0], 1'b1};
                end
            end

            if (cs_rising && active) begin
                active  <= 1'b0;
                rx_data <= rx_shift;
                done    <= 1'b1;
            end
        end
    end
endmodule