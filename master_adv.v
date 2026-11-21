module master_adv #(
    parameter MAX_WIDTH = 16,
    parameter CLK_DIV_MAX = 8'd7
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [MAX_WIDTH-1:0] data_in,
    input wire miso,
    input wire cpha,
    input wire cpol,
    input wire [4:0] word_len,
    output reg mosi,
    output reg sck,
    output reg cs,
    output reg [MAX_WIDTH-1:0]data_out,
    output reg busy
);
//DEFINING STATE PARAMS
localparam IDLE =2'b00;
localparam TRANSFER = 2'b01;
localparam FINISH = 2'b10;

reg [1:0] state;
reg [MAX_WIDTH-1:0] tx_shift_reg;
reg [MAX_WIDTH-1:0] rx_shift_reg;
reg [4:0] bit_count;

reg [7:0]clk_div_counter;
reg spi_clk_edge;
reg sck_prev;

wire sample_edge;
wire shift_edge;

wire sck_rising = (sck == 1'b1 && sck_prev == 1'b0);
wire sck_falling = (sck == 1'b0 && sck_prev == 1'b1);

assign sample_edge = (cpha==1'b0) ?((cpol==1'b0)? sck_rising:sck_falling):
                                  ((cpol==1'b0)? sck_falling:sck_rising);
assign shift_edge = (cpha==1'b0) ?((cpol==1'b0)? sck_falling:sck_rising):
                                  ((cpol==1'b0)? sck_rising:sck_falling);

// RUNNING THE CLOCK ONLY FOR THE TRANSFER STATE FOR BETTER RESULT AND MAKING IT 0 OTHERWISE
always @(posedge clk or posedge rst) begin
    if(rst) begin
        clk_div_counter <=8'b0;
        spi_clk_edge <= 1'b0;
    end else begin
        if(state==TRANSFER)begin
        if(clk_div_counter == CLK_DIV_MAX) begin
            clk_div_counter <= 8'b0;
            spi_clk_edge <=1'b1;
        end else begin
            clk_div_counter <= clk_div_counter + 1'b1;
            spi_clk_edge <= 1'b0;
        end
        end else begin
            clk_div_counter <= 8'b0;
            spi_clk_edge <= 1'b0;
        end
end
end

//MAKING THE FSM 
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state <= IDLE;
        bit_count <= 5'b0;
        tx_shift_reg <= {MAX_WIDTH{1'b0}};
        rx_shift_reg <= {MAX_WIDTH{1'b0}};
        cs <= 1'b1;
        busy <= 1'b0;
        data_out <={MAX_WIDTH{1'b0}};
        sck <= 1'b0;
        sck_prev <=1'b0;
        mosi <= 1'b0;
    end else begin
        sck_prev <= sck;
        case (state)
            IDLE : begin
                cs <= 1'b1;
                busy <= 1'b0;
                sck <= cpol;
                mosi <= 1'b0;
                bit_count <= 5'b0;

                if(start) begin
                    cs <= 1'b0;
                    busy <=1'b1;

                    tx_shift_reg <= data_in << (MAX_WIDTH-word_len);

                    if(cpha == 1'b0) begin
                        mosi <= data_in[word_len-1];
                        tx_shift_reg <= (data_in << (MAX_WIDTH - word_len)) <<1;
                    end
                    state <= TRANSFER;
                end
            end
            TRANSFER: begin
                if(spi_clk_edge) begin
                    sck <=~sck;
                end
                if(sample_edge) begin
                    rx_shift_reg <= {rx_shift_reg[MAX_WIDTH - 2:0],miso};
                    bit_count <= bit_count +1'b1;
                end
                if(shift_edge) begin
                    if(bit_count == word_len) begin
                        state <= FINISH;
                    end
                    else begin
                        mosi <= tx_shift_reg[MAX_WIDTH -1];
                        tx_shift_reg <={tx_shift_reg[MAX_WIDTH-2:0],1'b1};
                    end
                end
            end
            FINISH: begin
                  cs <= 1'b1;
                busy <=1'b0;
                state<=IDLE;
                sck <= cpol;
                data_out <= rx_shift_reg;
            end
            default: state <=IDLE;
        endcase
    end
end

endmodule
