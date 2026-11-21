`timescale 1ns/1ps

module tb_master_adv;

    localparam MAX_WIDTH   = 16;
    localparam CLK_DIV_MAX = 8'd3;   // small divider -> faster sim, still exercises the divider logic
    localparam CLK_PERIOD  = 10;

    reg                   clk;
    reg                   rst;
    reg                   start;
    reg  [MAX_WIDTH-1:0]  data_in;
    reg                   cpha;
    reg                   cpol;
    reg  [4:0]            word_len;
    wire                  mosi;
    wire                  sck;
    wire                  cs;
    wire [MAX_WIDTH-1:0]  data_out;
    wire                  busy;

    wire                  miso;
    reg  [MAX_WIDTH-1:0]  slave_tx_data;
    wire [MAX_WIDTH-1:0]  slave_rx_data;
    wire                  slave_done;

    integer pass_count;
    integer fail_count;
    integer i;

    // ---- DUT ----
    master_adv #(
        .MAX_WIDTH  (MAX_WIDTH),
        .CLK_DIV_MAX(CLK_DIV_MAX)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .data_in (data_in),
        .miso    (miso),
        .cpha    (cpha),
        .cpol    (cpol),
        .word_len(word_len),
        .mosi    (mosi),
        .sck     (sck),
        .cs      (cs),
        .data_out(data_out),
        .busy    (busy)
    );

    // ---- Loopback slave model ----
    spi_slave_model #(
        .MAX_WIDTH(MAX_WIDTH)
    ) slave (
        .clk     (clk),
        .rst     (rst),
        .sck     (sck),
        .cs      (cs),
        .mosi    (mosi),
        .miso    (miso),
        .cpol    (cpol),
        .cpha    (cpha),
        .word_len(word_len),
        .tx_data (slave_tx_data),
        .rx_data (slave_rx_data),
        .done    (slave_done)
    );

    // ---- Clock ----
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Waveform dump ----
    initial begin
        $dumpfile("tb_master_adv.vcd");
        $dumpvars(0, tb_master_adv);
    end

    // ---- Reset task ----
    task do_reset;
        begin
            rst   = 1'b1;
            start = 1'b0;
            @(posedge clk);
            @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    // ---- Run a single transfer and self-check both directions ----
    task run_transfer;
        input [1:0]           mode;        // 0..3 -> {cpol,cpha}
        input [4:0]            wlen;
        input [MAX_WIDTH-1:0]  m_tx;
        input [MAX_WIDTH-1:0]  s_tx;
        input [255:0]          label;       // test name for logging
        reg [MAX_WIDTH-1:0] expected_master_rx;
        reg [MAX_WIDTH-1:0] expected_slave_rx;
        integer timeout;
        begin
            cpol          = mode[1];
            cpha          = mode[0];
            word_len      = wlen;
            data_in       = m_tx;
            slave_tx_data = s_tx;

            // mask expected values to word_len bits (bits above word_len are don't-care)
            expected_master_rx = s_tx & ((wlen == 5'd16) ? 16'hFFFF : ((16'h1 << wlen) - 16'h1));
            expected_slave_rx  = m_tx & ((wlen == 5'd16) ? 16'hFFFF : ((16'h1 << wlen) - 16'h1));

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // wait for busy to deassert (transfer finished), with a timeout guard
            timeout = 0;
            while (busy !== 1'b0 && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            // one extra cycle for FINISH -> IDLE data_out latch to settle
            @(posedge clk);
            @(posedge clk);

            if (timeout >= 100000) begin
                $display("[FAIL] %0s : TIMEOUT waiting for transfer to complete", label);
                fail_count = fail_count + 1;
            end else if ((data_out & ((wlen==5'd16)?16'hFFFF:((16'h1<<wlen)-16'h1))) !== expected_master_rx) begin
                $display("[FAIL] %0s : master data_out mismatch. got=%h expected=%h (cpol=%0d cpha=%0d wlen=%0d)",
                          label, data_out, expected_master_rx, cpol, cpha, wlen);
                fail_count = fail_count + 1;
            end else if ((slave_rx_data & ((wlen==5'd16)?16'hFFFF:((16'h1<<wlen)-16'h1))) !== expected_slave_rx) begin
                $display("[FAIL] %0s : slave rx mismatch. got=%h expected=%h (cpol=%0d cpha=%0d wlen=%0d)",
                          label, slave_rx_data, expected_slave_rx, cpol, cpha, wlen);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %0s : cpol=%0d cpha=%0d wlen=%0d m_tx=%h s_tx=%h -> master_rx=%h slave_rx=%h",
                          label, cpol, cpha, wlen, m_tx, s_tx, data_out, slave_rx_data);
                pass_count = pass_count + 1;
            end

            // small gap between transfers
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        start   = 1'b0;
        cpol    = 1'b0;
        cpha    = 1'b0;
        word_len= 5'd8;
        data_in = 16'h0;
        slave_tx_data = 16'h0;

        do_reset;

        // ---------------------------------------------------------
        // Directed test: all 4 SPI modes, fixed data, 8-bit words
        // ---------------------------------------------------------
        run_transfer(2'b00, 5'd8, 16'hA5, 16'h3C, "Mode0_basic_8b"); // CPOL0 CPHA0
        run_transfer(2'b01, 5'd8, 16'hA5, 16'h3C, "Mode1_basic_8b"); // CPOL0 CPHA1
        run_transfer(2'b10, 5'd8, 16'hA5, 16'h3C, "Mode2_basic_8b"); // CPOL1 CPHA0
        run_transfer(2'b11, 5'd8, 16'hA5, 16'h3C, "Mode3_basic_8b"); // CPOL1 CPHA1

        // ---------------------------------------------------------
        // Full-width (16-bit) transfers, all 4 modes
        // ---------------------------------------------------------
        run_transfer(2'b00, 5'd16, 16'hDEAD, 16'hBEEF, "Mode0_full16");
        run_transfer(2'b01, 5'd16, 16'hDEAD, 16'hBEEF, "Mode1_full16");
        run_transfer(2'b10, 5'd16, 16'hDEAD, 16'hBEEF, "Mode2_full16");
        run_transfer(2'b11, 5'd16, 16'hDEAD, 16'hBEEF, "Mode3_full16");

        // ---------------------------------------------------------
        // Minimal word length (1 bit), all 4 modes
        // ---------------------------------------------------------
        run_transfer(2'b00, 5'd1, 16'h1, 16'h1, "Mode0_1bit");
        run_transfer(2'b01, 5'd1, 16'h1, 16'h0, "Mode1_1bit");
        run_transfer(2'b10, 5'd1, 16'h0, 16'h1, "Mode2_1bit");
        run_transfer(2'b11, 5'd1, 16'h0, 16'h0, "Mode3_1bit");

        // ---------------------------------------------------------
        // Odd word length (12 bits), all 4 modes
        // ---------------------------------------------------------
        run_transfer(2'b00, 5'd12, 16'h0FA5, 16'h0C3C, "Mode0_12b");
        run_transfer(2'b01, 5'd12, 16'h0FA5, 16'h0C3C, "Mode1_12b");
        run_transfer(2'b10, 5'd12, 16'h0FA5, 16'h0C3C, "Mode2_12b");
        run_transfer(2'b11, 5'd12, 16'h0FA5, 16'h0C3C, "Mode3_12b");

        // ---------------------------------------------------------
        // All-zeros and all-ones patterns (stuck-bit detection)
        // ---------------------------------------------------------
        run_transfer(2'b00, 5'd8, 16'h00, 16'h00, "Mode0_allzero");
        run_transfer(2'b00, 5'd8, 16'hFF, 16'hFF, "Mode0_allone");
        run_transfer(2'b11, 5'd8, 16'h00, 16'hFF, "Mode3_zero_one_mix");
        run_transfer(2'b11, 5'd8, 16'hFF, 16'h00, "Mode3_one_zero_mix");

        // ---------------------------------------------------------
        // Back-to-back transfers with no reset in between, all modes
        // ---------------------------------------------------------
        for (i = 0; i < 4; i = i + 1) begin
            run_transfer(i[1:0], 5'd8, 16'h55 + i, 16'hAA + i, "BackToBack");
        end

        // ---------------------------------------------------------
        // Randomized regression across all 4 modes and varying word lengths
        // ---------------------------------------------------------
        for (i = 0; i < 40; i = i + 1) begin
            begin : rand_draw
                reg [1:0] r_mode;
                reg [4:0] r_wlen;
                reg [MAX_WIDTH-1:0] r_mtx, r_stx;
                r_mode = $unsigned($random);                        // 0..3
                r_wlen = ($unsigned($random) % MAX_WIDTH) + 1;       // single draw, clamped to 1..16
                r_mtx  = $unsigned($random);
                r_stx  = $unsigned($random);
                run_transfer(r_mode, r_wlen, r_mtx, r_stx, "Random");
            end
        end

        // ---------------------------------------------------------
        // Reset applied mid-transfer: DUT must return cleanly to IDLE
        // ---------------------------------------------------------
        cpol = 1'b0; cpha = 1'b0; word_len = 5'd8;
        data_in = 16'hC3; slave_tx_data = 16'h3D;
        @(posedge clk); start = 1'b1; @(posedge clk); start = 1'b0;
        repeat (3) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        if (busy !== 1'b0 || cs !== 1'b1 || dut.state !== 2'b00) begin
            $display("[FAIL] Mid-transfer reset : DUT did not return to a clean IDLE state");
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Mid-transfer reset : DUT returned to clean IDLE state");
            pass_count = pass_count + 1;
        end
        // confirm the DUT still works normally after the async reset
        run_transfer(2'b00, 5'd8, 16'h5A, 16'hA5, "PostReset_sanity");

        // ---------------------------------------------------------
        // Summary
        // ---------------------------------------------------------
        $display("--------------------------------------------------");
        $display("TOTAL PASS = %0d, TOTAL FAIL = %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_count);
        $display("--------------------------------------------------");

        $finish;
    end

    // Global watchdog
    initial begin
        #2000000;
        $display("[FAIL] GLOBAL WATCHDOG TIMEOUT - simulation hung");
        $finish;
    end

endmodule