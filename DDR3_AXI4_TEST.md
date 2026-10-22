# DDR3 AXI4 直接仿真

本项目现在由 testbench2 直接驱动 MIG 的 AXI4 接口，并连接两颗 x16 DDR3 模型。已删除 rd、wr、driver、top 四个自定义 RTL 模块。

testbench2 分为数据产生、AW/W/B 写通道、AR/R 读通道三部分，文件后部是 MIG/DDR3 的公共仿真连接和测试流程。

在 Vivado Tcl Console 执行：

```tcl
source {D:/CodeRepository/FPGA_Project/K325T_DDR3_AXI4/scripts/start_testbench2.tcl}
```

更多说明见 [DDR3_AXI4_DUPLEX.md](DDR3_AXI4_DUPLEX.md)。