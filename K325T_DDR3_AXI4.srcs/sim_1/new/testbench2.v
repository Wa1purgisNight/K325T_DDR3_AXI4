`timescale 1ns / 1ps
// Direct AXI4 stimulus -> MIG -> two x16 DDR3 models. No driver/wrapper RTL.
module testbench2;
    parameter integer BURST_LEN=64, NUM_BURSTS=4;
    localparam integer BEATS=BURST_LEN*NUM_BURSTS;
    localparam [29:0] READ_BASE=30'h00000000, WRITE_BASE=30'h08000000;

    // =====================================================================
    // 1. 数据产生：准备写数据和读回期望值
    // =====================================================================
    reg [63:0] data_a[0:BEATS-1];
    reg [63:0] data_b[0:BEATS-1];
    reg [63:0] data_b_new[0:BEATS-1];
    integer i;
    function [63:0] make_data;
        input [29:0] addr;
        reg [31:0] a;
        begin
            a={2'b00,addr};
            make_data={a ^ 32'hA5A55A5A,~a};
        end
    endfunction
    initial begin
        if (BURST_LEN<1 || BURST_LEN>256 ||
            (BURST_LEN & (BURST_LEN-1))!=0 || NUM_BURSTS<1 || NUM_BURSTS>16 ||
            BEATS*8>30'h08000000)
            $fatal(1,"Invalid parameters: burst count must be 1..16 (unique 4-bit IDs)");
        for (i=0;i<BEATS;i=i+1) begin
            data_a[i]=make_data(READ_BASE+i*8);
            data_b[i]=make_data(WRITE_BASE+i*8);
            // Different data proves that the concurrent write actually happened.
            data_b_new[i]=data_b[i] ^ 64'h3C3CC3C3_00000000;
        end
    end

    // =====================================================================
    // 2. 写通道：AW 写地址、W 写数据、B 写应答
    // =====================================================================
    // AW channel
    reg  [3:0]   axi_awid=0;
    reg  [29:0]  axi_awaddr=0;
    reg  [7:0]   axi_awlen=0;
    reg  [2:0]   axi_awsize=0;
    reg  [1:0]   axi_awburst=0;
    reg          axi_awlock=0;
    reg  [3:0]   axi_awcache=0;
    reg  [2:0]   axi_awprot=0;
    reg  [3:0]   axi_awqos=0;
    reg          axi_awvalid=0;
    wire         axi_awready;

    // W channel
    reg  [63:0]  axi_wdata=0;
    reg  [7:0]   axi_wstrb=0;
    reg          axi_wlast=0;
    reg          axi_wvalid=0;
    wire         axi_wready;

    // B channel
    wire [3:0]   axi_bid;
    wire [1:0]   axi_bresp;
    wire         axi_bvalid;
    reg          axi_bready=0;

    task send_aw;
        input [29:0] base;
        integer b;
        begin
            @(negedge ui_clk);
            axi_awid=0; axi_awlen=BURST_LEN-1; axi_awsize=3;
            axi_awburst=1; axi_awqos=1; axi_awvalid=1;
            for (b=0;b<NUM_BURSTS;b=b+1) begin
                axi_awid=b[3:0];
                axi_awaddr=base+b*BURST_LEN*8;
                @(posedge ui_clk);
                while (!axi_awready) @(posedge ui_clk);
                $display("AW: phase=%0d ID=%0d ADDR=%h",test_phase,axi_awid,axi_awaddr);
                @(negedge ui_clk);
            end
            axi_awvalid=0;
        end
    endtask
    task send_w;
        input integer data_set; // 0: A, 1: baseline B, 2: new B
        integer j;
        begin
            @(negedge ui_clk);
            axi_wstrb=8'hff; axi_wvalid=1;
            for (j=0;j<BEATS;j=j+1) begin
                case (data_set)
                    0: axi_wdata=data_a[j];
                    1: axi_wdata=data_b[j];
                    2: axi_wdata=data_b_new[j];
                endcase
                axi_wlast=(j%BURST_LEN==BURST_LEN-1);
                @(posedge ui_clk);
                while (!axi_wready) @(posedge ui_clk);
                @(negedge ui_clk);
            end
            axi_wvalid=0;
        end
    endtask
    task receive_b;
        integer b;
        reg [15:0] received_ids;
        begin
            received_ids=0;
            @(negedge ui_clk); axi_bready=1;
            for (b=0;b<NUM_BURSTS;b=b+1) begin
                @(posedge ui_clk);
                while (!axi_bvalid) @(posedge ui_clk);
                if ((^axi_bid) === 1'bx || axi_bid>=NUM_BURSTS || axi_bresp !== 2'b00)
                    $fatal(1,"B error: ID=%h RESP=%h",axi_bid,axi_bresp);
                // Different IDs may respond in a different order than AW.
                if (received_ids[axi_bid]) $fatal(1,"Duplicate BID=%0d",axi_bid);
                received_ids[axi_bid]=1;
                $display("B: phase=%0d ID=%0d RESP=%b",test_phase,axi_bid,axi_bresp);
            end
            @(negedge ui_clk); axi_bready=0;
        end
    endtask
    task write_job;
        input [29:0] base;
        input integer data_set;
        begin
            wr_busy=1;
            // AW and W launch independently. W does not wait for AWREADY.
            fork
                send_aw(base);
                send_w(data_set);
                receive_b;
            join
            wr_busy=0;
        end
    endtask

    // =====================================================================
    // 3. 读通道：AR 读地址、R 读数据及应答
    // =====================================================================
    // AR channel
    reg  [3:0]   axi_arid=0;
    reg  [29:0]  axi_araddr=0;
    reg  [7:0]   axi_arlen=0;
    reg  [2:0]   axi_arsize=0;
    reg  [1:0]   axi_arburst=0;
    reg          axi_arlock=0;
    reg  [3:0]   axi_arcache=0;
    reg  [2:0]   axi_arprot=0;
    reg  [3:0]   axi_arqos=0;
    reg          axi_arvalid=0;
    wire         axi_arready;

    // R channel
    wire [3:0]   axi_rid;
    wire [63:0]  axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rlast;
    wire         axi_rvalid;
    reg          axi_rready=0;

    task send_ar;
        input [29:0] base;
        integer b;
        begin
            @(negedge ui_clk);
            axi_arid=0; axi_arlen=BURST_LEN-1; axi_arsize=3;
            axi_arburst=1; axi_arqos=1; axi_arvalid=1;
            for (b=0;b<NUM_BURSTS;b=b+1) begin
                axi_arid=b[3:0];
                axi_araddr=base+b*BURST_LEN*8;
                @(posedge ui_clk);
                while (!axi_arready) @(posedge ui_clk);
                $display("AR: phase=%0d ID=%0d ADDR=%h",test_phase,axi_arid,axi_araddr);
                @(negedge ui_clk);
            end
            axi_arvalid=0;
        end
    endtask
    task receive_r;
        input integer data_set;
        integer j, id, index;
        integer beat_count[0:15];
        reg [63:0] expected;
        begin
            for (id=0;id<16;id=id+1) beat_count[id]=0;
            @(negedge ui_clk); axi_rready=1;
            for (j=0;j<BEATS;j=j+1) begin
                @(posedge ui_clk);
                while (!axi_rvalid) @(posedge ui_clk);
                if ((^axi_rid) === 1'bx || axi_rid>=NUM_BURSTS)
                    $fatal(1,"Unexpected RID=%h",axi_rid);
                id=axi_rid;
                if (beat_count[id]>=BURST_LEN) $fatal(1,"Extra R beat for RID=%0d",id);
                // Each RID selects its own burst and beat counter. Responses
                // may arrive out of order or interleave between different IDs.
                index=id*BURST_LEN+beat_count[id];
                case (data_set)
                    0: expected=data_a[index];
                    1: expected=data_b[index];
                    2: expected=data_b_new[index];
                endcase
                if (axi_rdata !== expected ||
                    axi_rresp !== 2'b00 || axi_rlast !== (beat_count[id]==BURST_LEN-1))
                    $fatal(1,"R mismatch: phase=%0d beat=%0d expected=%h actual=%h ID=%h RESP=%h LAST=%b",
                        test_phase,beat_count[id],expected,axi_rdata,axi_rid,axi_rresp,axi_rlast);
                beat_count[id]=beat_count[id]+1;
                if (axi_rlast) $display("R: phase=%0d ID=%0d burst complete",test_phase,id);
            end
            for (id=0;id<NUM_BURSTS;id=id+1)
                if (beat_count[id]!=BURST_LEN) $fatal(1,"Incomplete burst RID=%0d",id);
            @(negedge ui_clk); axi_rready=0;
        end
    endtask
    task read_job;
        input [29:0] base;
        input integer data_set;
        begin
            rd_busy=1;
            fork
                send_ar(base);
                receive_r(data_set);
            join
            rd_busy=0;
        end
    endtask

    // Common simulation wiring: clocks/reset, MIG and DDR3 devices.
    reg sys_clk_i=0, clk_ref_i=0, sys_rst_n=0;
    always #1.25 sys_clk_i=~sys_clk_i; // 400 MHz
    always #2.5 clk_ref_i=~clk_ref_i;  // 200 MHz
    wire [31:0] ddr3_dq;
    wire [3:0] ddr3_dqs_n;
    wire [3:0] ddr3_dqs_p;
    wire [14:0] ddr3_addr;
    wire [2:0] ddr3_ba;
    wire ddr3_ras_n;
    wire ddr3_cas_n;
    wire ddr3_we_n;
    wire ddr3_reset_n;
    wire ddr3_ck_p;
    wire ddr3_ck_n;
    wire ddr3_cke;
    wire ddr3_cs_n;
    wire ddr3_odt;
    wire [3:0] ddr3_dm;
    wire ui_clk, ui_clk_sync_rst, init_calib_complete;

    reg [1:0] reset_release=0;
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) reset_release<=0;
        else reset_release<={reset_release[0],1'b1};
    end
    wire axi_aresetn=reset_release[1];
    mig_7series_0 u_mig (
        // Clock, reset and non-AXI connections
        .ddr3_dq                 (ddr3_dq),
        .ddr3_dqs_n              (ddr3_dqs_n),
        .ddr3_dqs_p              (ddr3_dqs_p),
        .ddr3_addr               (ddr3_addr),
        .ddr3_ba                 (ddr3_ba),
        .ddr3_ras_n              (ddr3_ras_n),
        .ddr3_cas_n              (ddr3_cas_n),
        .ddr3_we_n               (ddr3_we_n),
        .ddr3_reset_n            (ddr3_reset_n),
        .ddr3_ck_p               (ddr3_ck_p),
        .ddr3_ck_n               (ddr3_ck_n),
        .ddr3_cke                (ddr3_cke),
        .ddr3_cs_n               (ddr3_cs_n),
        .ddr3_odt                (ddr3_odt),
        .ddr3_dm                 (ddr3_dm),
        .sys_clk_i               (sys_clk_i),
        .clk_ref_i               (clk_ref_i),
        .sys_rst                 (sys_rst_n),
        .ui_clk                  (ui_clk),
        .ui_clk_sync_rst         (ui_clk_sync_rst),
        .mmcm_locked             (),
        .aresetn                 (axi_aresetn),
        .init_calib_complete     (init_calib_complete),
        .app_sr_req              (1'b0),
        .app_ref_req             (1'b0),
        .app_zq_req              (1'b0),
        .app_sr_active           (),
        .app_ref_ack             (),
        .app_zq_ack              (),
        .device_temp_i           (12'h000),
        .device_temp             (),

        // AW - write address
        .s_axi_awid              (axi_awid),
        .s_axi_awaddr            (axi_awaddr),
        .s_axi_awlen             (axi_awlen),
        .s_axi_awsize            (axi_awsize),
        .s_axi_awburst           (axi_awburst),
        .s_axi_awlock            (axi_awlock),
        .s_axi_awcache           (axi_awcache),
        .s_axi_awprot            (axi_awprot),
        .s_axi_awqos             (axi_awqos),
        .s_axi_awvalid           (axi_awvalid),
        .s_axi_awready           (axi_awready),

        // W - write data
        .s_axi_wdata             (axi_wdata),
        .s_axi_wstrb             (axi_wstrb),
        .s_axi_wlast             (axi_wlast),
        .s_axi_wvalid            (axi_wvalid),
        .s_axi_wready            (axi_wready),

        // B - write response
        .s_axi_bid               (axi_bid),
        .s_axi_bresp             (axi_bresp),
        .s_axi_bvalid            (axi_bvalid),
        .s_axi_bready            (axi_bready),

        // AR - read address
        .s_axi_arid              (axi_arid),
        .s_axi_araddr            (axi_araddr),
        .s_axi_arlen             (axi_arlen),
        .s_axi_arsize            (axi_arsize),
        .s_axi_arburst           (axi_arburst),
        .s_axi_arlock            (axi_arlock),
        .s_axi_arcache           (axi_arcache),
        .s_axi_arprot            (axi_arprot),
        .s_axi_arqos             (axi_arqos),
        .s_axi_arvalid           (axi_arvalid),
        .s_axi_arready           (axi_arready),

        // R - read data/response
        .s_axi_rid               (axi_rid),
        .s_axi_rdata             (axi_rdata),
        .s_axi_rresp             (axi_rresp),
        .s_axi_rlast             (axi_rlast),
        .s_axi_rvalid            (axi_rvalid),
        .s_axi_rready            (axi_rready)
    );

    genvar chip;
    generate for (chip=0;chip<2;chip=chip+1) begin : memory
        ddr3_model #(.DEBUG(0)) u_ddr3 (
            .rst_n(ddr3_reset_n), .ck(ddr3_ck_p), .ck_n(ddr3_ck_n),
            .cke(ddr3_cke), .cs_n(ddr3_cs_n), .ras_n(ddr3_ras_n),
            .cas_n(ddr3_cas_n), .we_n(ddr3_we_n), .ba(ddr3_ba),
            .addr(ddr3_addr), .dm_tdqs(ddr3_dm[chip*2 +: 2]),
            .dq(ddr3_dq[chip*16 +: 16]), .dqs(ddr3_dqs_p[chip*2 +: 2]),
            .dqs_n(ddr3_dqs_n[chip*2 +: 2]), .tdqs_n(), .odt(ddr3_odt)
        );
    end endgenerate

    // Common test sequencing and measurement (all traffic is on MIG ui_clk).
    reg [2:0] test_phase=0;
    reg wr_busy=0, rd_busy=0, test_done=0, test_pass=0;
    integer cycles[0:6], aw_count[0:6], w_count[0:6], b_count[0:6];
    integer ar_count[0:6], r_count[0:6];
    integer p, overlap_cycles=0, same_cycle_beats=0;
    reg aw_stalled=0, w_stalled=0, ar_stalled=0;
    reg [58:0] saved_aw, saved_ar;
    reg [72:0] saved_w;
    wire [58:0] aw_payload={axi_awid,axi_awaddr,axi_awlen,axi_awsize,
        axi_awburst,axi_awlock,axi_awcache,axi_awprot,axi_awqos};
    wire [58:0] ar_payload={axi_arid,axi_araddr,axi_arlen,axi_arsize,
        axi_arburst,axi_arlock,axi_arcache,axi_arprot,axi_arqos};
    wire [72:0] w_payload={axi_wdata,axi_wstrb,axi_wlast};
    initial for (p=0;p<7;p=p+1) begin
        cycles[p]=0; aw_count[p]=0; w_count[p]=0; b_count[p]=0;
        ar_count[p]=0; r_count[p]=0;
    end
    always @(posedge ui_clk) begin
        if (!axi_aresetn) begin aw_stalled=0; w_stalled=0; ar_stalled=0; end
        else begin
            if (aw_stalled && (!axi_awvalid || aw_payload !== saved_aw))
                $fatal(1,"AW changed during backpressure");
            if (w_stalled && (!axi_wvalid || w_payload !== saved_w))
                $fatal(1,"W changed during backpressure");
            if (ar_stalled && (!axi_arvalid || ar_payload !== saved_ar))
                $fatal(1,"AR changed during backpressure");
            aw_stalled=axi_awvalid && !axi_awready; saved_aw=aw_payload;
            w_stalled=axi_wvalid && !axi_wready; saved_w=w_payload;
            ar_stalled=axi_arvalid && !axi_arready; saved_ar=ar_payload;
            if (!init_calib_complete && (axi_awvalid || axi_wvalid || axi_arvalid))
                $fatal(1,"AXI traffic before calibration");
            if (test_phase>=1 && test_phase<=5) begin
                cycles[test_phase]=cycles[test_phase]+1;
                if (axi_awvalid && axi_awready) aw_count[test_phase]=aw_count[test_phase]+1;
                if (axi_wvalid && axi_wready) w_count[test_phase]=w_count[test_phase]+1;
                if (axi_bvalid && axi_bready) b_count[test_phase]=b_count[test_phase]+1;
                if (axi_arvalid && axi_arready) ar_count[test_phase]=ar_count[test_phase]+1;
                if (axi_rvalid && axi_rready) r_count[test_phase]=r_count[test_phase]+1;
                if (test_phase==4 && wr_busy && rd_busy) overlap_cycles=overlap_cycles+1;
                if (test_phase==4 && axi_wvalid && axi_wready && axi_rvalid && axi_rready)
                    same_cycle_beats=same_cycle_beats+1;
            end
        end
    end
    task check_counts;
        input integer phase_num, writes, reads;
        begin
            if (aw_count[phase_num]!=writes || b_count[phase_num]!=writes ||
                w_count[phase_num]!=writes*BURST_LEN || ar_count[phase_num]!=reads ||
                r_count[phase_num]!=reads*BURST_LEN)
                $fatal(1,"Transaction count mismatch at phase %0d",phase_num);
        end
    endtask
    task report;
        input integer phase_num;
        input [127:0] label;
        real write_mbps, read_mbps;
        begin
            write_mbps=w_count[phase_num]*8.0*1000.0/(cycles[phase_num]*10.0);
            read_mbps=r_count[phase_num]*8.0*1000.0/(cycles[phase_num]*10.0);
            $display("%0s: cycles=%0d write=%0.2f MB/s read=%0.2f MB/s total=%0.2f MB/s",
                label,cycles[phase_num],write_mbps,read_mbps,write_mbps+read_mbps);
        end
    endtask
    initial begin
        #200; sys_rst_n=1;
        wait (init_calib_complete === 1 && axi_aresetn === 1);
        $display("MIG calibrated at %t",$time);
        @(negedge ui_clk); test_phase=1; write_job(READ_BASE,0);
        @(negedge ui_clk); test_phase=2; read_job(READ_BASE,0);
        @(negedge ui_clk); test_phase=3; write_job(WRITE_BASE,1);
        @(negedge ui_clk); test_phase=4;
        fork
            write_job(WRITE_BASE,2);
            read_job(READ_BASE,0);
        join
        @(negedge ui_clk); test_phase=5; read_job(WRITE_BASE,2);
        @(negedge ui_clk); test_phase=6;
        check_counts(1,NUM_BURSTS,0); check_counts(2,0,NUM_BURSTS);
        check_counts(3,NUM_BURSTS,0); check_counts(4,NUM_BURSTS,NUM_BURSTS);
        check_counts(5,0,NUM_BURSTS);
        if (overlap_cycles==0) $fatal(1,"Read/write tasks never overlapped");
        report(2,"READ_ONLY"); report(3,"WRITE_ONLY"); report(4,"DUPLEX");
        $display("OVERLAP: busy cycles=%0d same-cycle W/R=%0d",overlap_cycles,same_cycle_beats);
        // Physical DDR is shared; same-cycle W/R is a result, not a requirement.
        test_done=1; test_pass=1;
        repeat (8) @(negedge ui_clk);
        if (axi_awvalid || axi_wvalid || axi_arvalid) $fatal(1,"Unexpected extra traffic");
        $display("PASS: testbench2 concurrent read/write and post-write verification");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1,"testbench2 timeout: phase=%0d",test_phase);
    end
endmodule
