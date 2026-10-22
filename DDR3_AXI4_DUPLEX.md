# testbench2 直接驱动 MIG

当前结构只有 `testbench2.v`、MIG 核和两颗 x16 DDR3 仿真模型。原来的 ddr3_axi_wr、ddr3_axi_rd、ddr3_driver、ddr3_top 已删除，旧快速存储模型与旧 testbench 入口也已清理。

## 代码组织

`K325T_DDR3_AXI4.srcs/sim_1/new/testbench2.v` 按三部分组织学习代码：

1. **数据产生**：预先生成 data_a、data_b、data_b_new 三组 64 位数据。新 B 数据用于确认并发阶段确实更新了 DDR。
2. **AW、W、B 写通道**：端口信号、send_aw、send_w、receive_b 和 write_job。三个任务并行运行，WVALID 不等待 AWREADY。
3. **AR、R 读通道**：端口信号、send_ar、receive_r 和 read_job。两个任务并行运行，读回数据、RID、RRESP、RLAST 都在 receive_r 中检查。

文件后部为公共仿真连接、MIG 实例、DDR3 模型、测试流程与带宽统计。读地址通道的标准名称是 AR。

AXI 信号直接连接到 `u_mig.s_axi_*`，没有中间的 driver 或缓冲模块。数据宽度 64 位、地址宽度 30 位、ID 宽度 4 位。每个 burst 使用不同 AWID/ARID：默认 4 组分别为 0、1、2、3；AWSIZE/ARSIZE=3，INCR 突发，WSTRB=8'hff，QoS=1。

每个阶段重新使用这组 ID，进入下一阶段前已收完上一阶段的响应。B 通道按 BID 检查响应是否重复；R 通道为每个 RID 分别计数，用 `RID*BURST_LEN+该ID的拍序号` 查找期望数据。因此不同 ID 的 B/R 返回顺序可以不同，读数据也可以在不同 ID 之间交错。W 通道仍按 AW 提交顺序发送数据，AXI4 没有 WID。

日志打印 AW/AR 的 ID 和起始地址、BID，以及每个 RID 的突发完成事件，便于和波形对应。

多 ID 修改已通过真实 MIG 编译展开检查。独立提取 B/R 校验任务的仿真通过了逆序 BID 和交错 RID 的正常用例，并检测到重复 BID、非法 RID、错误数据及错误 RLAST；这不代表实际 MIG 一定会乱序返回。

系统时钟 400 MHz、参考时钟 200 MHz、MIG ui_clk 100 MHz。全部 AXI 任务使用 ui_clk；在负边沿更新主设备输出，在正边沿判断 VALID && READY。反压时保持 VALID 和载荷。等待 init_calib_complete 和 axi_aresetn 都为 1 后才开始请求。

## 测试流程

默认每个方向 4 组突发，每组 64 拍，共 2 KiB，可修改 BURST_LEN、NUM_BURSTS。BURST_LEN 支持 1..256 的二次幂；NUM_BURSTS 支持 1..16，每组使用一个独立的 4 位 ID。全宽突发不会跨越 4 KiB 边界。

| test_phase | 操作 |
|---|---|
| 1 | 写 A：0x00000000 |
| 2 | 单读并校验 A |
| 3 | 单写 B：0x08000000 |
| 4 | fork 同时读 A、写新数据到 B |
| 5 | 读 B，校验并发阶段写入的新数据 |
| 6 | 完成 |

A/B 位于不同 bank，避免同地址读写竞争。testbench 检查写应答、读数据和 LAST、事务数量、主设备反压稳定性，并报告单读、单写、并发带宽以及同周期 W/R 握手次数。带宽统计包含任务启动和响应排空，排除校准、预填充和最终校验。DDR 物理数据总线仍由读写共享。

## 运行

Vivado Tcl Console 执行：

```tcl
source {D:/CodeRepository/FPGA_Project/K325T_DDR3_AXI4/scripts/start_testbench2.tcl}
```

脚本关闭旧仿真、清理打开工程里的旧模块引用，在 sim_duplex 中启动 testbench2。波形：

```tcl
source scripts/testbench2_wave.tcl
restart
run all
```

批量完整仿真：

```powershell
vivado -mode batch -source scripts/run_testbench2.tcl
```

仅编译和展开检查：

```powershell
vivado -mode batch -source scripts/check_testbench2.tcl
```

编译检查使用 sim_direct_check，避免占用 sim_1 的日志。完整仿真成功时输出 `PASS: testbench2 concurrent read/write and post-write verification`，2 ms 仿真时间内未结束会报超时。

2026-10-10：简化后的 testbench2、真实 MIG 与 DDR3 模型已通过编译和展开检查。本次未运行完整校准及带宽仿真；之前版本的带宽数据不适用于当前直接连接结构。
