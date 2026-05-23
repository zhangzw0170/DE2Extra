# 当前初始化顺序梳理：上电到进入 `de2shell`

> 范围：仅覆盖当前已经实现的链路，不包含未来 RTOS 启动、任务调度和驱动框架。
> 目标：回答“板子上电后，为什么会进入某个程序、哪些外设已经活着、`de2shell` 在哪里真正开始”。

---

## 1. 先分清两件事

当前工程里，“源码里存在 `de2shell`”和“板子上当前运行的是 `de2shell`”不是一回事。

- `sw/app/de2shell/` 只是一个可编译应用目录。
- FPGA 里真正会上电执行的程序，取决于最近一次 `build.sh` 编译时传入的 `app/...` 参数。
- `build.sh` 的默认应用是 `app/sdram_test`，不是 `app/de2shell`。

对应流程见 [build.sh](/build.sh:1)：

1. 在 Docker 里编译 `sw/${APP}`
2. 生成 `neorv32/rtl/core/neorv32_imem_image.vhd`
3. 复制到 [src/rtl/neorv32_imem_image.vhd](/src/rtl/neorv32_imem_image.vhd:1)
4. Quartus 重新综合/布局布线
5. 烧录新的 `.sof`

所以要进入 `de2shell`，前提是最近一次使用的是：

```bash
./build.sh --flash app/de2shell
```

如果最近一次烧的是 `app/ps2_test`、`app/sdram_test` 或别的程序，那么 CPU 上电后就不会进入 shell。

---

## 2. 硬件侧启动顺序

### 2.1 FPGA 配置完成

USB-Blaster 或 Quartus Programmer 把 `par/de2extra.sof` 下载到 FPGA 后，逻辑开始运行。

顶层入口是 [src/rtl/de2_115_top.vhd](/src/rtl/de2_115_top.vhd:17) 的 `de2_115_top`。

### 2.2 时钟和全局复位

[src/rtl/glue/clk_rst_gen.vhd](/src/rtl/glue/clk_rst_gen.vhd:1) 做了两件事：

- 通过 PLL 生成：
  - `clk_50m_o`：CPU/主逻辑 50 MHz
  - `clk_100m_o`：SDRAM 内部控制时钟
  - `clk_100m_shift_o`：送到板级 SDRAM 芯片引脚的相移时钟
- 生成复位：
  - `KEY[0]` 按下时异步拉低复位
  - 复位释放还要等待 `pll_locked`

当前复位输出逻辑见 [clk_rst_gen.vhd](/src/rtl/glue/clk_rst_gen.vhd:43)：

- `rst_n_o = rst_sync(2) and pll_locked`

结论：

- 没锁 PLL，不会放行系统复位
- 按住 `KEY[0]`，整个 SoC 保持复位

### 2.3 SDRAM 专用复位再同步

在顶层里，`rst_n` 释放后还不会立刻让 SDRAM 控制器工作。

[src/rtl/de2_115_top.vhd](/src/rtl/de2_115_top.vhd:198) 又把复位同步到 `clk_sdram` 域，生成 `rst_sdram_n`，避免 SDRAM 状态机异步出复位。

顺序是：

1. `rst_n` 释放
2. `clk_sdram` 域打两拍
3. `rst_sdram_n` 才置 1

---

## 3. 顶层里哪些模块会在 CPU 启动前就活着

顶层 `de2_115_top` 在复位释放后会同时启动这些硬件模块：

- `neorv32_wrapper`：CPU 核
- `wb_intercon`：XBUS 地址解码
- `sdram_ctrl`：SDRAM 控制器
- `vga_text_terminal`：VGA 文本终端硬件
- `ps2_controller`：PS/2 键盘控制器
- `uart_jtag_bridge + jtag_uart_0`：把 UART0 TX 镜像到 JTAG 观察通道
- `lcd_status`：LCD 状态显示

对应位置见 [src/rtl/de2_115_top.vhd](/src/rtl/de2_115_top.vhd:224) 之后。

这意味着，即使 CPU 程序还没开始“做事”，部分外设已经有默认行为：

- `vga_text_terminal` 已经在输出 VGA 时序
- `ps2_controller` 已经开始监听 PS/2 总线
- `lcd_status` 已经接管 LCD 引脚
- `UART_TXD` 已经连到 CPU UART0，同时被 JTAG 桥旁路监听

---

## 4. CPU 是怎么开始执行软件的

### 4.1 CPU 配置

NEORV32 封装在 [src/rtl/neorv32_wrapper.vhd](/src/rtl/neorv32_wrapper.vhd:13)。

当前和启动最相关的 generic 是：

- `IMEM_EN => true`
- `IMEM_BASE => x"00000000"`
- `DMEM_BASE => x"80000000"`
- `XBUS_EN => true`
- `BOOT_MODE_SELECT => BOOT_MODE`

而顶层给 `BOOT_MODE` 传的是 `2`，见 [de2_115_top.vhd](/src/rtl/de2_115_top.vhd:229)。

当前注释定义是：

- `0 = bootloader`
- `2 = IMEM image`

所以当前启动模式是：

- CPU 复位释放后，直接从 IMEM 镜像启动
- 不走串口 bootloader 交互

### 4.2 IMEM 镜像来源

CPU 执行的第一份程序，来自 [src/rtl/neorv32_imem_image.vhd](/src/rtl/neorv32_imem_image.vhd:1)。

这个文件不是手写源码，而是最近一次构建应用时由 `make image` 生成后拷贝进来的。

因此：

- 这份 VHDL 镜像就是“当前板上程序”的唯一真相
- 如果 shell 表现和你以为的不一致，先查最近一次 `build.sh` 烧的是什么 app

---

## 5. `de2shell` 自己的软件初始化顺序

假设当前 IMEM 烧进去的就是 `app/de2shell`，那么软件入口是 [sw/app/de2shell/main.c](/sw/app/de2shell/main.c:266)。

### 5.1 静态初值阶段

在 `main()` 运行前，关键静态变量已经有默认值：

- `active_prog = PROG_SHELL`
- `programs[]` 已经指向各个子程序描述符

这意味着：

- shell 是默认前台程序
- 上电不会先自动进入 `hello`、`memtest` 或 `crypto`

### 5.2 `main()` 最早的 3 个动作

当前 `main()` 里，进入主循环前只有这几步：

1. `neorv32_rte_setup();`
2. `uart_init();`
3. `vga_init();`
4. `shell_init();`
5. `board_status_refresh();`
6. `draw_status_bar();`

见 [sw/app/de2shell/main.c](/sw/app/de2shell/main.c:267) 和 [sw/app/de2shell/main.c](/sw/app/de2shell/main.c:273)。

#### `neorv32_rte_setup()`

- 建立 NEORV32 运行时异常环境
- 为后续 trap / exception 提供基础

#### `uart_init()`

当前仅做：

- `neorv32_uart0_setup(115200, 0);`

见 [sw/app/de2shell/main.c](/sw/app/de2shell/main.c:43)。

作用：

- 打开 UART0，供 shell 轮询接收键盘输入

#### `vga_init()`

当前 shell 的显示完全依赖 VGA HAL，见 [sw/app/de2shell/vga_hal.c](/sw/app/de2shell/vga_hal.c:66)。

它会做：

1. 向 VGA 清屏寄存器写 1
2. 使能文本终端和光标闪烁
3. 设置背景色
4. 光标归零

#### `shell_init()`

它会：

1. 再次清屏
2. 光标移到 `(0,0)`
3. 打印：
   - `DE2Extra Shell v0.1`
   - `Type 'help' for commands.`

见 [sw/app/de2shell/main.c](/sw/app/de2shell/main.c:126)。

#### `draw_status_bar()`

它会在最后一行画状态栏，显示当前频道号和程序名。

初始时 `active_prog = PROG_SHELL`，所以状态栏应该显示 shell。

#### `board_status_refresh()`

它负责把 shell 当前状态编码到 GPIO 输出，交给 `lcd_status` 和 HEX/LED 侧做常驻显示。

当前 shell 空闲态约定为：

- LCD 第一行：`DE2Extra Shell`
- LCD 第二行：`CH0 SHEL READY`
- HEX/状态字：带一个心跳位翻转，证明主循环没有卡死

此外，顶层已经把 `KEY1..KEY3` 接入 `gpio_in[20:18]`，所以 shell 启动后立刻具备下面这些板上快捷操作：

- `SW[3:0]`：选择目标 program id
- `KEY1`：进入当前选择的程序
- `KEY2`：强制返回 shell
- `KEY3`：重绘当前页面

---

## 6. 进入 shell 后的运行模型

当前 `de2shell` 不是中断驱动，也不是 RTOS 任务模型，而是一个单线程轮询循环。

主循环见 [sw/app/de2shell/main.c](/sw/app/de2shell/main.c:277)。

顺序如下：

1. 轮询 UART 是否收到字符
2. 轮询 `KEY1..KEY3` 的边沿事件
3. 如果当前前台是 `PROG_SHELL`，就调用 `shell_input(c)`
4. 否则把输入转发给当前活动程序的 `input()`
5. 调用当前活动程序的 `update()`
6. 如果该程序 `finish()` 返回真，则回到 shell
7. 刷新板级状态字并重画状态栏
8. 做一个忙等延时

所以当前 shell 的本质是：

- 输入：UART 轮询
- 显示：VGA 文本缓冲
- 调度：单循环 cooperative 风格
- 没有任务切换
- 没有统一驱动初始化阶段
- 没有设备管理层

---

## 7. 当前“进入 shell 前”哪些外设其实还没接进来

这部分对后续 RTOS 很重要，因为它决定了哪些东西属于真正的系统启动链，哪些只是“以后要接”。

### 已经在启动链里的

- 时钟/复位
- CPU + IMEM
- XBUS / SDRAM
- VGA 文本终端硬件
- PS/2 控制器硬件
- JTAG-UART 镜像链路

### 还没有真正成为 shell 启动链一部分的

- LCD：当前仍由 `lcd_status` 常驻驱动，`de2shell` 没有接管 LCD
- PS/2 输入到 shell：PS/2 控制器已经存在，但 `de2shell` 当前主输入源仍是 UART，不是键盘
- IR：`handle_ir()` 已写，但主循环里还没有真实取 IR 事件的路径
- 定时器：虽然地址空间预留了 `ADDR_TIMER_BASE`，当前 shell 没用它做调度
- 中断控制器：地址预留了 `ADDR_INTC_BASE`，当前 shell 仍以轮询为主

---

## 8. 当前阶段最容易混淆的 4 个点

### 8.1 “为什么 shell 没起来？”

先看最近烧的 app 不是 `de2shell` 就行。

如果最近执行的是：

```bash
./build.sh --flash app/ps2_test
```

那板子上运行的就是 `ps2_test`，不是 shell。

### 8.2 “为什么串口没看到 shell banner？”

因为当前 `shell_init()` 的输出走的是 `vga_puts()`，不是 `uart_puts()`。

也就是说：

- shell 用 UART 收输入
- 但默认不往 UART 回显欢迎信息
- shell 的可见输出目标是 VGA 文本缓冲

### 8.3 “为什么 LCD 上不是 shell 内容？”

因为当前顶层仍把 LCD 直接绑给 `lcd_status`，见 [src/rtl/de2_115_top.vhd](/src/rtl/de2_115_top.vhd:436) 之后的 LCD 连线。

`de2shell` 没有 LCD HAL，也没有 LCD 初始化过程。

### 8.4 “为什么键盘已经好用了，但 shell 还不能直接用键盘输入？”

因为“PS/2 控制器工作正常”和“shell 读取 PS/2 FIFO 作为控制台输入”是两件事。

当前只完成了前者，还没有把它接进 `de2shell` 的输入抽象层。

---

## 9. 给后续 RTOS 接入的直接启示

当前启动链将来拆成 RTOS 版本时，至少要分成下面几段：

1. **Boot image 选择**
   - 明确当前 bitstream 内嵌的是哪个应用镜像

2. **Board bring-up**
   - 时钟、复位、SDRAM、基础寄存器映射

3. **Early BSP init**
   - trap、UART、console、timer、heap、device table

4. **Driver init**
   - VGA、PS/2、IR、LCD、audio、storage

5. **RTOS kernel start**
   - tick、中断、任务创建、调度器启动

6. **UI / shell task start**
   - 控制台输入输出统一收口，不再让每个 app 自己碰硬件

当前这份文档对应的是第 1-4 段的“非 RTOS 基线”。

---

## 10. 当前结论

如果只看“上电到进入 `de2shell`”，当前顺序可以压缩成一句话：

1. 烧录时选定 app，生成并固化到 IMEM
2. FPGA 配置完成后，PLL 锁定并释放全局复位
3. 顶层同时启动 CPU、XBUS、SDRAM、VGA、PS/2、LCD 状态显示等硬件
4. CPU 从 IMEM `0x00000000` 直接执行当前 app
5. 若该 app 是 `de2shell`，则按 `RTE -> UART -> VGA -> shell banner -> status bar -> polling loop` 进入 shell

这就是当前版本最真实的初始化顺序。
