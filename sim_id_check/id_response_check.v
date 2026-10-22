`timescale 1ns/1ps
module id_response_check;
    parameter integer FAULT=0;
    localparam integer BURST_LEN=4, NUM_BURSTS=4, BEATS=16;
    reg ui_clk=0;
    always #5 ui_clk=~ui_clk;
    reg [2:0] test_phase=4;
    reg [3:0] axi_bid=0, axi_rid=0;
    reg [1:0] axi_bresp=0, axi_rresp=0;
    reg axi_bvalid=0, axi_rvalid=0, axi_rlast=0;
    reg axi_bready=0, axi_rready=0;
    reg [63:0] axi_rdata=0;
    reg [63:0] data_a[0:15],data_b[0:15],data_b_new[0:15];
    integer k, beat, n, response_id;
    reg b_done=0, r_done=0;
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
    initial begin
        for (k=0;k<BEATS;k=k+1) begin
            data_a[k]=64'h1234000000000000+k;
            data_b[k]=0; data_b_new[k]=0;
        end
        fork
            begin receive_b; b_done=1; end
            begin receive_r(0); r_done=1; end
            begin
                for (n=3;n>=0;n=n-1) begin
                    @(negedge ui_clk);
                    axi_bid=(FAULT==1 && n==0)?3:n;
                    axi_bvalid=1;
                    @(posedge ui_clk);
                    while (!axi_bready) @(posedge ui_clk);
                end
                @(negedge ui_clk); axi_bvalid=0;
            end
            begin
                for (beat=0;beat<BURST_LEN;beat=beat+1)
                    for (response_id=3;response_id>=0;response_id=response_id-1) begin
                        @(negedge ui_clk);
                        axi_rid=(FAULT==2 && beat==0 && response_id==3)?4:response_id;
                        axi_rdata=data_a[response_id*BURST_LEN+beat];
                        if (FAULT==3 && beat==1 && response_id==2) axi_rdata=axi_rdata^1;
                        axi_rlast=(beat==BURST_LEN-1);
                        if (FAULT==4 && beat==0 && response_id==3) axi_rlast=1;
                        axi_rvalid=1;
                        @(posedge ui_clk);
                        while (!axi_rready) @(posedge ui_clk);
                    end
                @(negedge ui_clk); axi_rvalid=0;
            end
        join
        if (!b_done || !r_done) $fatal(1,"Responses did not finish");
        $display("PASS: reversed BID and interleaved RID");
        $finish;
    end
    initial begin #10000; $fatal(1,"Response checker timeout"); end
endmodule
