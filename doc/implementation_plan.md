# DE2Extra 实现计划

> NEORV32 (RISC-V) + FreeRTOS + LVGL — 让 DE2-115 变成一台完整的计算机

## 总览

| 项目 | 内容 |
|------|------|
| CPU | NEORV32 (RV32IMC + Zicsr + Zicntr + Zfinx + Zk*) |
| OS | FreeRTOS |
| GUI | LVGL 720p (1280×720@60Hz, RGB565) |
| 密码学 | RISC-V Crypto ISA (AES, SHA-256/512, SM4, SM3) |
| 平台 | DE2-115 (Cyclone IV), 移植目标: 达芬奇 A7Pro |
| 仓库 | https://github.com/zhangzw0170/DE2Extra |

---

## 阶段划分

### Phase 0: 基础设施 (1-2 周) ✅ 已完成

**目标**: 最小系统能跑起来 — CPU 上板 + LED/HEX 验证 + UART 输出

#### 0.1 NEORV32 集成 ✅
- [x] 配置 NEORV32 (RV32IMC + Zfinx + Zk* + UART + GPIO + TRNG + XBUS + OCD)
- [x] 编写顶层 `de2_115_top.vhd`，实例化 NEORV32
- [x] Phase 0 无 PLL，50MHz 直通
- [x] 引脚约束: 时钟、复位、UART、LEDR、HEX0-3、SDRAM (已对照 xlsx 核对)
- [x] GPIO 扩展到 32 位，LEDR 和 HEX 使用不重叠的位段

#### 0.2 Quartus 项目搭建 ✅
- [x] 创建 `par/de2extra.qpf` / `.qsf`
- [x] 添加所有源文件到项目
- [x] 配置时序约束 (`.sdc`)
- [x] 综合 + fitter 通过 (~7500 LCs, 15 DSPs)

#### 0.3 仿真环境 ✅
- [x] 编写 `tb_de2_115_top.vhd` — 顶层 testbench

#### 0.4 软件工具链 ✅
- [x] Docker 容器化 RISC-V GCC 14.3 (xPack) — 不污染宿主环境
- [x] 复用 NEORV32 软件框架 (crt0, neorv32.ld, common.mk)
- [x] `sw/build.sh` 一条命令编译 + 生成 IMEM image

#### 0.5 上板验证 ✅
- [x] CPU 启动运行，GPIO 输出正常
- [x] LED 跑马灯、HEX 计数器、UART 输出均通过

**当前例程预期行为** (`sw/app/hello/main.c`):
- LEDR[17:0]: 跑马灯，单个 LED 从 LEDR[0] 到 LEDR[17] 循环点亮
- HEX0-3: 四位十六进制计数器 0000 → FFFF 循环
- LEDG[0]: 复位指示灯（按住 KEY[0] 亮，松开灭）
- UART (115200 baud): 输出 "DE2Extra — NEORV32 RISC-V alive!" + 定期心跳

**信号映射**:
- GPIO[17:0] → LEDR[17:0]
- GPIO[31:16] → HEX3..0（seg7_mapper 解码）
- GPIO_DIR: 全 32 位输出
- Boot mode 2: IMEM image 烧入 bitstream，上电即跑

---

### Phase 1: 核心外设 (2-3 周)

**目标**: CPU 能访问 SDRAM + UART + 定时器 + 中断，足以跑 FreeRTOS

#### 1.1 SDRAM 控制器 (`sdram_ctrl.vhd`)
- [ ] SDRAM 初始化时序 (ISSI IS42S16400J-7TL, 128MB, 16-bit)
- [ ] 自动刷新管理 (7.8125μs 间隔)
- [ ] 读写状态机
- [ ] Wishbone → 寄存器接口适配 (`wb_sdram_adapter.vhd`)
- [ ] 验证: 仿真读写正确性
- [ ] 验证: CPU 读写 SDRAM 数据一致

**关键参数**:
- SDRAM 时钟: 100MHz (PLL 2x)
- CAS Latency: 3
- Burst Length: 1 (单次访问) / Full Page (帧缓冲)
- 总线带宽分配: CPU 63% + VGA 37%

#### 1.2 系统定时器 (`timer_module.vhd`)
- [ ] 32-bit 可配置定时器，支持 FreeRTOS tick (configTICK_RATE_HZ = 1000)
- [ ] 中断产生 (溢出/匹配)
- [ ] 寄存器接口: [0] 当前值, [4] 重载值, [8] 控制位, [C] 状态/清除
- [ ] 验证: 定时精度 ±1 tick

#### 1.3 中断控制器 (`interrupt_ctrl.vhd`)
- [ ] 优先级中断仲裁 (8+ 中断源)
- [ ] 中断向量表
- [ ] 中断屏蔽/使能
- [ ] 寄存器接口: [0] pending, [4] enable, [8] vector, [C] clear
- [ ] 中断源映射:
  - IRQ0: 定时器 (最高优先级)
  - IRQ1: PS/2 键盘
  - IRQ2: PS/2 鼠标
  - IRQ3: UART
  - IRQ4: VGA 垂直同步
  - IRQ5: SD 卡
  - IRQ6: 音频 DMA
  - IRQ7: 以太网

#### 1.4 UART 增强
- [ ] 使用 NEORV32 内置 UART (调试串口)
- [ ] 波特率 115200
- [ ] 验证: 全双工通信

#### 1.5 Wishbone 总线互联
- [ ] 编写 `wb_intercon.vhd` — 多外设地址解码
- [ ] 地址空间分配:

| 起始地址 | 大小 | 外设 |
|----------|------|------|
| 0x00000000 | 64KB | NEORV32 内部 RAM |
| 0x01000000 | 128MB | SDRAM (CPU 数据 + 帧缓冲) |
| 0xF0000000 | 4KB | VGA 控制器 |
| 0xF0001000 | 4KB | PS/2 键盘 |
| 0xF0002000 | 4KB | PS/2 鼠标 |
| 0xF0003000 | 4KB | 系统定时器 |
| 0xF0004000 | 4KB | 中断控制器 |
| 0xF0005000 | 4KB | SPI (SD 卡) |
| 0xF0006000 | 4KB | I2C 主机 |
| 0xF0007000 | 4KB | 音频 I2S |
| 0xF0008000 | 4KB | LCD 控制器 |
| 0xF0009000 | 4KB | IR 接收器 |
| 0xF000A000 | 4KB | 以太网 MAC |
| 0xF000B000 | 4KB | GPIO 扩展 |

#### 1.6 FreeRTOS 移植
- [ ] 移植 FreeRTOS 到 NEORV32 (RV32IMC)
- [ ] 实现 `port.c` / `portmacro.h`:
  - 上下文保存/恢复
  - tick 中断 (连接 timer_module)
  - 临界区 (CSR mie 关中断)
- [ ] 堆管理: heap_4 (SDRAM 作为 FreeRTOS 堆)
- [ ] 验证: 多任务切换、信号量、队列

---

### Phase 2: 显示与输入 (2-3 周)

**目标**: 720p VGA 显示 + PS/2 键盘输入 + 能跑 LVGL

#### 2.1 VGA 控制器 (`vga_controller.vhd`)
- [ ] 720p 时序生成 (1280×720@60Hz):
  - Pixel clock: 74.25MHz
  - H_TOTAL = 1650, V_TOTAL = 750
  - H_SYNC = 80, V_SYNC = 5
  - H_BP = 220, V_BP = 20
  - H_FP = 110, V_FP = 5
- [ ] SDRAM 帧缓冲读取 (RGB565 → RGB888 DAC)
- [ ] 双缓冲支持 (减少撕裂)
- [ ] 光标叠加层 (硬件鼠标光标, 32×32)
- [ ] 寄存器接口: [0] 帧缓冲基址, [4] 分辨率, [8] 光标位置, [C] 控制
- [ ] 验证: 720p 显示色条图案

**帧缓冲计算**:
- 单帧: 1280 × 720 × 2 bytes (RGB565) = 1,843,200 bytes ≈ 1.76MB
- 双缓冲: 3.52MB (SDRAM 128MB 内微不足道)
- VGA 带宽: 74.25MHz × 2 bytes = 148.5MB/s (SDRAM 200MB/s 的 74%)

#### 2.2 PS/2 键盘 (`ps2_keyboard.vhd`)
- [ ] PS/2 协议: 11-bit 帧 (start + 8-data + parity + stop)
- [ ] Scan code 解码 (Set 2)
- [ ] 通码/断码处理
- [ ] FIFO 缓冲 (16-entry)
- [ ] 按键中断
- [ ] 验证: 按键扫描码通过 UART 输出

#### 2.3 PS/2 鼠标 (`ps2_mouse.vhd`)
- [ ] PS/2 鼠标协议 (3/4-byte 包)
- [ ] 鼠标初始化 (设置 stream 模式)
- [ ] 鼠标位置追踪 + 中断
- [ ] 验证: 鼠标坐标通过 UART 输出

#### 2.4 LVGL 移植
- [ ] 移植 LVGL 到 FreeRTOS 环境
- [ ] 显示驱动: 帧缓冲直写 (RGB565)
- [ ] 输入驱动: PS/2 键盘 + 鼠标
- [ ] 基础 UI: 窗口、按钮、文本
- [ ] 验证: LVGL 按钮点击 → UART 打印事件

---

### Phase 3: 实验整合 — 硬件 (2-3 周)

**目标**: 13 个实验全部作为 FreeRTOS 任务整合进来

每个实验实现为:
- **硬件** (可选加速): VHDL 模块挂载到总线
- **软件**: FreeRTOS 任务 + LVGL 界面
- **入口**: LVGL 菜单选择 → 启动对应任务

| # | 实验 | 硬件实现 | 软件任务 | 备注 |
|---|------|----------|----------|------|
| 1 | 3-8 译码器 | — | SW 输入 → LED 输出 | 纯软件模拟 |
| 2 | LED 显示 | — | SW 控制 LED 图案 | 纯软件 |
| 3 | 七段数码管 + 时钟 | — | 定时器驱动数码管 | 软件时钟 |
| 4 | 双端口 RAM | — | SDRAM 读写演示 | 软件模拟 |
| 5 | FSM 序列检测器 | — | 状态机软件模拟 + VGA 可视化 | 教学演示 |
| 6 | VGA 色条 | VGA 硬件 | 色条/灰度条图案 | 已有 VGA 控制器 |
| 7 | VGA 动画 | VGA 硬件 | 简单图形/弹球动画 | LVGL canvas |
| 8 | PS/2 键盘 | PS/2 硬件 | 键盘输入显示 | 已有 PS/2 模块 |
| 9 | (缺失) | — | — | 无 Exp9 |
| 10 | IR NEC 解码 | IR 硬件 | 红外遥控器解码显示 | `irda_receiver.vhd` |
| 11 | DDS 合成器 | PWM/DAC | 正弦波/方波/三角波输出 | 音频模块协助 |
| 12 | 简单 CPU | — | CPU 仿真器 + 可视化 | 教学演示 |
| 13 | LCD 控制 | LCD 硬件 | HD44780 文字显示 | `lcd_controller.vhd` |

#### 3.1 实验菜单系统
- [ ] LVGL 主菜单: 网格布局，每个实验一个按钮
- [ ] 实验启动/停止: 任务创建/删除
- [ ] 资源冲突检测: 同时只能运行一个 VGA 实验
- [ ] 返回主菜单

#### 3.2 各实验实现 (按优先级)
- [ ] Exp6: VGA 色条 (复用 VGA 控制器)
- [ ] Exp8: PS/2 键盘 (复用 PS/2 模块)
- [ ] Exp13: LCD 显示
- [ ] Exp3: 七段数码管时钟
- [ ] Exp7: VGA 动画 (LVGL canvas)
- [ ] Exp10: IR 解码
- [ ] Exp1/2: LED 实验组合
- [ ] Exp4: RAM 读写
- [ ] Exp5: FSM 可视化
- [ ] Exp11: DDS 合成器
- [ ] Exp12: CPU 仿真器

---

### Phase 4: 密码学演示 (2-3 周)

**目标**: 利用 NEORV32 的 RISC-V Crypto ISA 扩展，实现交互式密码学演示

#### 4.1 密码学硬件/软件

| 算法 | ISA 扩展 | 实现方式 | 演示内容 |
|------|----------|----------|----------|
| AES-128/256 | Zkne/Zknd | 软件指令 | 加密/解密文件，VGA 显示轮密钥 |
| SHA-256/512 | Zknh | 软件指令 | 哈希计算，显示哈希值 |
| SM4 (国密) | Zksed | 软件指令 | 国密对称加密演示 |
| SM3 (国密) | Zksh | 软件指令 | 国密哈希演示 |
| 位操作 | Zbkb/Zbkc/Zbkx | 软件指令 | 底层原语演示 |
| 自定义密码 | Xcfu | 硬件 | 用户自定义密码协处理器 |

#### 4.2 密码学 UI
- [ ] LVGL 密码学菜单页
- [ ] 各算法独立页面:
  - 输入区 (键盘输入明文/密钥)
  - 执行按钮
  - 结果显示区 (十六进制/ASCII)
  - 性能统计 (周期数、时间)
- [ ] 算法对比视图: 同一输入不同算法结果对比

#### 4.3 密码学测试向量
- [ ] NIST AES 测试向量验证
- [ ] NIST SHA 测试向量验证
- [ ] 国密标准测试向量验证
- [ ] 随机测试 (NEORV32 TRNG 生成输入)

---

### Phase 5: 扩展外设 (3-4 周)

**目标**: 补全剩余外设，系统功能完整

#### 5.1 SD 卡 (`spi_sd_card.vhd`)
- [ ] SPI 模式初始化
- [ ] FAT32 只读文件系统 (软件)
- [ ] 用途: 存储图片资源、测试数据、密码学输入文件
- [ ] 验证: 读取 SD 卡文件通过 UART 输出

#### 5.2 I2C 主机 (`i2c_master.vhd`)
- [ ] 通用 I2C 主机控制器
- [ ] 配置 WM8731 音频 CODEC
- [ ] 配置 ADV7180 TV 解码器
- [ ] 读取 EEPROM (32Kbit)
- [ ] 验证: 读写 EEPROM 数据

#### 5.3 音频 I2S (`audio_i2s.vhd`)
- [ ] I2S 时序生成 (WM8731)
- [ ] DMA 通道: SDRAM → I2S
- [ ] 采样率: 8kHz / 44.1kHz / 48kHz
- [ ] DDS 合成器接入 (Exp11)
- [ ] 验证: 播放正弦波

#### 5.4 LCD 控制器 (`lcd_controller.vhd`)
- [ ] HD44780 4-bit 并行接口
- [ ] 字符显示 + 自定义字符
- [ ] 验证: LCD 显示文字

#### 5.5 IR 接收器 (`irda_receiver.vhd`)
- [ ] NEC 协议解码
- [ ] 红外遥控器按键映射
- [ ] 验证: 遥控器按键显示

#### 5.6 以太网 MAC (`eth_mac.vhd`) — 可选
- [ ] MII/RMII 接口 (Marvell 88E1111)
- [ ] 基础 UDP 收发
- [ ] 可能用途: 远程调试、数据传输

#### 5.7 USB OTG (`usb_ctrl.vhd`) — 可选
- [ ] ISP1362 寄存器接口
- [ ] HID 设备支持
- [ ] 可能用途: 外接键盘/鼠标/存储

---

### Phase 6: 系统优化与移植 (2-3 周)

**目标**: 性能优化 + 移植到达芬奇 A7Pro

#### 6.1 性能优化
- [ ] SDRAM 访问优化: burst 读取代换单次读取 (帧缓冲)
- [ ] CPU 指令缓存配置
- [ ] LVGL 渲染优化: 部分刷新、脏区域跟踪
- [ ] FreeRTOS 任务优先级调优
- [ ] 资源占用报告 (LUT、FF、RAM、DSP)

#### 6.2 达芬奇 A7Pro 移植
- [ ] 替换顶层引脚约束
- [ ] 替换 PLL 配置 (不同时钟频率)
- [ ] 外设模块 VHDL **零修改** (验证平台无关性)
- [ ] 验证: A7Pro 上所有功能正常

#### 6.3 文档与发布
- [ ] 用户手册 (使用说明)
- [ ] 开发者文档 (添加新外设/新实验)
- [ ] 架构图 (block diagram)
- [ ] 录制演示视频

---

## 依赖关系

```
Phase 0 ──→ Phase 1 ──→ Phase 2 ──→ Phase 3
                │            │
                │            └──→ Phase 4 (可与 Phase 3 并行)
                │
                └──→ Phase 5 (Phase 1 完成后可开始)
                        │
                        └──→ Phase 6
```

## 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| SDRAM 带宽不足 | VGA 闪烁 | 降低帧率或分辨率；burst 读取优化 |
| NEORV32 性能不够 | LVGL 帧率低 | 减少动画；优化 LVGL 配置；硬件加速 |
| Cyclone IV 资源不足 | 综合失败 | 裁剪外设；关闭不需要的 NEORV32 特性 |
| Crypto ISA 工具链问题 | 密码演示无法运行 | 退回软件实现 (查表法) |
| FreeRTOS 移植复杂度 | 进度延迟 | 先跑裸机程序验证硬件 |

## 里程碑

| 里程碑 | 完成条件 | 目标日期 |
|--------|----------|----------|
| M1: 最小系统 | UART 输出 + SDRAM 读写 | Week 3 |
| M2: FreeRTOS 上板 | 多任务切换 + 定时器 | Week 5 |
| M3: 720p 显示 | VGA 显示 LVGL 界面 + 键盘输入 | Week 8 |
| M4: 实验整合 | 13 个实验全部可运行 | Week 11 |
| M5: 密码学演示 | AES/SHA/SM4/SM3 演示完成 | Week 13 |
| M6: 全功能系统 | 所有外设 + A7Pro 移植 | Week 16 |
