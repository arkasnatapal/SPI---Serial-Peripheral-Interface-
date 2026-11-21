module spi_master(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] data_in,
    input wire miso,
    output reg mosi,
    output reg sck,
    output reg cs,
    output reg [7:0] data_out,
    output reg busy
);

parameter IDLE = 2'b00;
parameter TRANSFER = 2'b01;
parameter FINISH = 2'b10;

reg [1:0] state;
reg [7:0] shift_reg; //shift register for outgoing data
reg [3:0] bit_count; // BIT COUNTER THAT WILL COUNT THE 8 BIT 
reg [7:0] clk_div_counter;
reg spi_clk_edge;


// CLOCK DIVIDER LOGIC
always @(posedge clk or posedge rst) begin
    if(rst) begin
        clk_div_counter<=8'b0;
        spi_clk_edge<=1'b0;
    end
    else begin
        if(clk_div_counter == 8'd15) begin
            spi_clk_edge <=1'b1;
            clk_div_counter <=8'b0;
        end else begin
            clk_div_counter <= clk_div_counter +1'b1;
            spi_clk_edge <= 1'b0;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        state <= IDLE;
        bit_count <= 4'b0;
        shift_reg <= 8'b0;
        cs <= 1'b1;
        busy <= 1'b0;
        data_out <=8'b0;
        sck <= 1'b0;
        mosi <= 1'b0;
    end else begin
        case(state)
            IDLE: begin
                cs <= 1'b1;
                busy <= 1'b0;
                sck <= 1'b0;
                mosi <= 1'b0;
                bit_count <= 4'b0;
                if(start) begin
                    shift_reg<=data_in;
                    busy <= 1'b1;
                    cs <= 1'b0;
                    state <= TRANSFER;
                end
            end
            TRANSFER: begin
                if(spi_clk_edge) begin
                    sck =~sck;
                    if(sck == 1) begin 
                        // HERE SCK == 1 THAT MEANS IT WILL LEAD TO A FALLING EDGE HERE WE WILL SHIFT TO OUR NEXT BIT OF DATA
                        if(bit_count == 4'd8) begin
                            state <= FINISH;
                        end else begin
                        mosi <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0],1'b0};
                    end
                    end else begin
                        // WHEN SCK == 0 THAT IS IN THE LEADING EDGE WE WILL READ THE BIT FROM THE MISO PIN
                        data_out <= {data_out[6:0],miso};
                        bit_count <= bit_count +1'b1;
                    end
            end
        end
            FINISH:begin
                cs <= 1'b1;
                busy <=1'b0;
                state<=IDLE;
            end
            default : begin
                state <= IDLE;
    end
        endcase
end     
end
endmodule