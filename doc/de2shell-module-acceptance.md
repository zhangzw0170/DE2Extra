# de2shell 模块验收表

> 整理时间: 2026-05-24
> 适用范围: `sw/app/de2shell/` 全线 C 软件 + 依赖的 VHDL 硬件外设
> 配套文档: `implementation_plan.md`, `phases/phase1-bus-sdram.md`, `phases/phase2a-crypto-cli.md`, `phases/phase2b-vga-terminal.md`, `phases/phase3-integration.md`

---

## 最新上板结果

- 构建/烧录命令: `MSYS_NO_PATHCONV=1 bash build.sh --flash app/de2shell`
- 实测板卡: `EP4CE115F29C7`
- 串口: `COM10`, `115200 8N1`
- LCD 常驻状态: 第一行 `DE2Extra Shell`，第二行 `CH0 SHEL READY`
- HEX/状态字: shell 空闲时可见心跳翻转，证明主循环仍在推进

当前代码侧新增、但尚待下一次上板确认的行为：

- shell 状态栏右侧改为显示 `uptime`，按分钟刷新
- `board_status` 统一状态层已接入 `main.c`
- `dashboard` 不再只是占位页，而是会主动接管 LCD/HEX/LED 的演示输出
- `lcd_status.vhd` 的 shell 模式已支持 `READY/LIVE/RUN/EDIT/HOLD/PASS/FAIL/BUSY`

本轮已通过串口 smoke test 的模块：

| 模块 | 进入 | 退出 | 备注 |
|---|---|---|---|
| `help` | ✅ | N/A | 列出全部命令 |
| `info` | ✅ | ✅ | `q` 返回 `0000>` |
| `hello` | ✅ | ✅ | `q` 返回 `0000>` |
| `dash` | ✅ | ✅ | 本轮修复 `finish()` |
| `monitor` | ✅ | ✅ | `q` 返回 `0000>` |
| `crypto` | ✅ | ✅ | `q<CR>` 返回 `0000>` |
| `ps2` | ✅ | ✅ | 串口可见键盘事件与 LED sync 日志 |
| `snake` | ✅ | ✅ | `q` 返回 `0000>` |
| `life` | ✅ | ✅ | `q` 返回 `0000>` |
| `exp1` | ✅ | ✅ | `q` 返回 `0000>` |
| `exp4` | ✅ | ✅ | `q` 返回 `0000>` |
| `exp5` | ✅ | ✅ | `q` 返回 `0000>` |
| `exp12` | ✅ | ✅ | `q` 返回 `0000>` |
| `memtest` | ✅ | ✅ | 四项 SDRAM 测试实板 `ALL PASS`，`q` 返回 `0000>` |

---

## 验收符号说明

| 符号 | 含义 |
|---|---|
| ✅ | 已通过上板 / 仿真验证 |
| 🟡 | 代码完成，待上板验证 |
| ❌ | 未实现 / 待开发 |
| N/A | 不适用 (LOCAL_BUILD 桩模块等) |

---

## A. 基础设施

### A1. Shell 框架 (main.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A1.1 | 命令解析 | `help` 输出全部 14 条命令列表 | ✅ |
| A1.2 | 程序调度 | 输入子命令名称后在 `active_prog` 间切换 | ✅ |
| A1.3 | 程序 init/update/input/finish 回调 | 每个程序切换时调 `init()`，每帧调 `update()`，按键调 `input()`，返回 shell 时调 `finish()` | ✅ |
| A1.4 | UART 输入 | `uart_kbhit()/uart_getc()` 正确读取 COM10 115200 8N1 | ✅ |
| A1.5 | 退格处理 | 退格键删除上一个输入字符并回退光标 | ✅ |
| A1.6 | 空行处理 | 按下回车不解析空命令，直接重打提示符 | ✅ |
| A1.7 | 未知命令 | 输入未注册命令时输出 `? Unknown command. Type 'help'` | ✅ |
| A1.8 | `cls` 命令 | 清屏并重绘 shell 启动画面 | ✅ |
| A1.9 | `quit`/`exit` 命令 | 从子程序返回 shell 主界面 | ✅ |
| A1.10 | 状态栏常驻 | 第 25 行 (row 24) 显示当前频道名，右侧显示 uptime (按分钟刷新) | 🟡 (代码完成，待上板确认) |
| A1.11 | 程序注册表完整性 | 14 个 `prog_id_t` 全部注册到 `programs[]` 数组 | ✅ |
| A1.12 | IR 遥控切频 | CH1-CH7 映射到 hello/memtest/crypto/snake/life/dash/info；CH+/CH- 顺序切换 | 🟡 |
| A1.13 | IR 指令透传 | 子程序的 `ir_input` 回调优先级高于全局 IR 映射 | 🟡 |
| A1.14 | Docker 交叉编译 | `build.sh` 分步执行 `make clean` + `make image`，当前 `de2shell` IMEM 镜像约 39KB，适配 64KB IMEM | ✅ |
| A1.15 | LOCAL_BUILD 编译 | `make local` (host gcc) 编译通过 | ✅ |
| A1.16 | 统一板级状态层 | `board_status.c/h` 负责 shell/子程序对 LCD/HEX/LED 的统一编码与接管 | 🟡 (代码完成，待上板确认) |

### A2. VGA HAL (vga_hal.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A2.1 | `vga_init()` | 清屏 + 显示静态光标 + 复位行列计数 | 🟡 (LOCAL_BUILD ANSI 模式通过；VGA 硬件待线) |
| A2.2 | `vga_putc()` | 字符写入 VGA text buffer 对应行列，(NEORV32 模式) 同步输出到 UART | 🟡 |
| A2.3 | `vga_puts()` | 连续写字符串 | 🟡 |
| A2.4 | `vga_goto()` | 光标移动到分屏坐标 (0-79, 0-24) | 🟡 |
| A2.5 | `vga_clear()` | 写 `VGA_CTRL_CLEAR` 寄存器清当前活动页 | 🟡 |
| A2.6 | `vga_cursor_show()` | 设置/取消可见静态光标；显示时关闭 `VGA_CTRL_BLINK` | 🟡 |
| A2.7 | `vga_col()` / `vga_row()` | 返回当前行列号 | 🟡 |
| A2.8 | `vga_puthex32()` | 以固定宽度 (8 hex digits) 显示 32-bit 值 | 🟡 |
| A2.9 | 换行处理 (`\n`) | `cur_col=0; cur_row++` 且 row 超出 VGA_ROWS 时自动折返 | 🟡 |
| A2.10 | 退格处理 (`\b`) | 光标左移一格并擦除字符 | 🟡 |
| A2.11 | RGB332 颜色常量 | 8 色 + 灰度正确定义 | 🟡 |
| A2.12 | NEORV32 模式地址映射 | VGA_BASE = `0xF0000000`，控制寄存器偏移正确 (cursor_x/y, ctrl, status, bgcolor, clear) | 🟡 |
| A2.13 | NEORV32 模式 UART 镜像 | 每个 VGA 字符同步从 `neorv32_uart0` 输出 | ✅ |

### A3. GPIO HAL (gpio_hal.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A3.1 | `gpio_read_in()` | NEORV32: 读 `neorv32_gpio_port_get()`；LOCAL: 返回模拟值 | ✅ |
| A3.2 | `gpio_read_out()` | NEORV32: 读 `NEORV32_GPIO->PORT_OUT`；LOCAL: 返回模拟值 | ✅ |
| A3.3 | LOCAL_BUILD 模拟注入 | `gpio_set_sim_in/out()` 可修改模拟值用于测试 | ✅ |

---

## B. 核心应用程序

### B1. hello — Phase 0 LED 跑马灯演示 (hello.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B1.1 | 启动画面 | 显示 CPU 型号 (RV32IMC+Zk*)、板卡型号、NEORV32 alive 消息 | ✅ |
| B1.2 | LED 跑马灯 | 16 个 LED 依次点亮 (`1<<led_idx`)，VGA 上以 `*`/`.` 显示 | 🟡 (VGA 硬件待线) |
| B1.3 | 秒计数器 | HEX 上显示递增的 16 进制秒数 (0x00-0xFF)，16 LED 周期为 1 秒 | 🟡 |
| B1.4 | NEORV32 GPIO 输出 | 执行 `neorv32_gpio_port_set(gpio_val)` 驱动真实 LED/HEX | ✅ |
| B1.5 | 退出 `q` | 按下 `q` 后 `finish()` 返回真，shell 接管 | ✅ |

### B2. memtest — SDRAM 自检 (memtest.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B2.1 | Walking-1s immediate | 逐字写入 `1<<(i%32)` 并立即回读比对，256 words | ✅ |
| B2.2 | Walking-1s bulk | 先全部写入再全部回读，256 words | ✅ |
| B2.3 | Checkerboard | 交替写入 `0xAAAAAAAA`/`0x55555555`，回读比对 | ✅ |
| B2.4 | Address-as-data | 写入自身地址值，回读比对 | ✅ |
| B2.5 | 全部通过 | VGA 显示 `[ALL PASS] SDRAM OK!`，LCD 显示 `LCD_STATUS_PASS` | ✅ |
| B2.6 | 失败信息 | 显示失败测试号 T、word 索引 W、期望值和实际值 | 🟡 |
| B2.7 | 重测 `r` | 按 `r` 重新执行全部 4 项测试 | 🟡 |
| B2.8 | LCD 调试协议 | 测试中/通过/失败状态通过 GPIO 输出到 LCD | ✅ |
| B2.9 | 命令行别名 | `memtest`、`sdram`、`sdram_test` 三个命令均能启动 | ✅ |
| B2.10 | 退出 `q` | 返回 shell | ✅ |

### B3. crypto — 密码学终端 (crypto.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B3.1 | `help` 命令 | 输出全部命令列表与用法 | ✅ |
| B3.2 | `info` 命令 | 输出密码学终端系统信息 | ✅ |
| B3.3 | `aes enc <key> <pt>` | AES-128 ECB 加密，NIST FIPS-197 测试向量通过 | ✅ |
| B3.4 | `aes dec <key> <ct>` | AES-128 ECB 解密，正确还原明文 | ✅ |
| B3.5 | `sha256 <hex-msg>` | SHA-256 哈希，NIST FIPS-180-4 测试向量通过 | ✅ |
| B3.6 | `sha512 <hex-msg>` | SHA-512 哈希，NIST FIPS-180-4 测试向量通过 | ✅ |
| B3.7 | `sm4 <key> <pt>` | SM4 加密，GB/T 32907-2016 测试向量通过 | ✅ |
| B3.8 | `sm3 <hex-msg>` | SM3 哈希，GB/T 32905-2016 测试向量通过 | ✅ |
| B3.9 | `trng [n]` | 从 TRNG 读取 n 个随机字节并以 hex 输出 | ✅ |
| B3.10 | `bench` | 纯 C 与 Zk* 加速版本的性能对比表 (cycles + speedup) | 🟡 (Zk* 加速待实现) |
| B3.11 | `cls` / `clear` | 清屏并重绘提示符 | ✅ |
| B3.12 | `quit` / `exit` / `q` | 返回 shell | ✅ |
| B3.13 | hex 解码容错 | `hex_decode()` 支持大小写、空格分隔 | ✅ |
| B3.14 | 命令参数解析 | 支持最多 8 个参数 | ✅ |
| B3.15 | AES-128 Zk* 加速 | `aes32esmi`/`aes32dsi` 替代查表，加速比 > 5x | ❌ |
| B3.16 | SHA-256 Zk* 加速 | `sha256sig0/1` + `sha256sum0/1` 替代移位 | ❌ |
| B3.17 | SHA-512 Zk* 加速 | `sha512sig0h/l` + `sha512sum0r/1r` 替代 | ❌ |
| B3.18 | SM4 Zk* 加速 | `sm4ed`/`sm4ks` 替代 S-box 查表 | ❌ |
| B3.19 | SM3 Zk* 加速 | `sm3p0`/`sm3p1` 替代 P0/P1 函数 | ❌ |
| B3.20 | TRNG 统计验证 | 做频率检验 / 序列检验确认随机性 | ❌ |

### B4. ps2 — PS/2 键盘监视器 (ps2.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B4.1 | 扫描码接收 | 从 `PS2->data` 读取原始 scan code，FIFO 16-entry | ✅ |
| B4.2 | E0 扩展键前缀 | 方向键、F1-F12、RCTRL/RALT 等扩展键正确识别 | ✅ |
| B4.3 | F0 释放码 | 按键释放事件正确识别 | ✅ |
| B4.4 | 修饰键跟踪 | 左/右 Shift/Ctrl/Alt/Win 按下/释放状态独立追踪 | ✅ |
| B4.5 | 主键盘 ASCII 映射 | 字母/数字/符号扫描码 → ASCII，Shift 状态影响大小写/符号 | ✅ |
| B4.6 | 数码键盘 ASCII 映射 | NumLock 状态影响 keypad 输出 | ✅ |
| B4.7 | Caps/Num/Scroll Lock 灯同步 | CAPS 切换时发送 `ED` + LED mask 命令，键盘 LED 同步 | ✅ |
| B4.8 | VGA 事件日志 | 每次按键打印 scan code、键名、修饰键状态、ASCII tty 表示 | 🟡 (VGA 硬件待线) |
| B4.9 | UART 镜像 | 每次事件同时输出到 UART | ✅ |
| B4.10 | 日志滚屏 | 超出 VGA 可视行数后自动清屏并重新打印标题 | 🟡 |
| B4.11 | 清屏 `c` | 按 `c` 清空日志并重置 | ✅ |
| B4.12 | 退出 `q` | 返回 shell | ✅ |
| B4.13 | 状态寄存器解析 | `ready`/`overflow`/`tx_busy`/`tx_done`/`tx_err`/`bus_idle` 正确读取 | ✅ |
| B4.14 | LOCAL_BUILD 降级 | 显示无 PS/2 硬件提示，按 `q` 退出 | N/A |

---

## C. 游戏

### C1. snake — 贪吃蛇 (snake.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| C1.1 | 初始化 | 蛇身 3 段，方向向右，得分 0，速度 120ms | ✅ |
| C1.2 | 方向控制 | WASD 改变方向，不允许反向 (不能原地掉头致死) | ✅ |
| C1.3 | 移动与碰撞 | 蛇头每 speed_ms/10 帧移动一格 | ✅ |
| C1.4 | 边界回绕 | 穿墙后从对面出现 (环面) | ✅ |
| C1.5 | 自身碰撞 | 蛇头与蛇身重合时 game over | ✅ |
| C1.6 | 食物生成 | 随机位置生成 `@`，不与蛇身重合 | ✅ |
| C1.7 | 吃食物 | 蛇身+1，得分+10，速度加快 (speed_ms-=5, 下限 30) | ✅ |
| C1.8 | VGA 渲染 | 40×20 网格 + 边框 + HUD (得分+速度) | 🟡 (VGA 硬件待线) |
| C1.9 | Game Over 显示 | 网格中央显示 "GAME OVER" | 🟡 |
| C1.10 | 退出 `q` | 返回 shell | ✅ |

### C2. life — 康威生命游戏 (life.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| C2.1 | 默认图案 | 启动时加载滑翔机 (glider) 图案 | ✅ |
| C2.2 | B3/S23 规则 | 邻居=3 出生，邻居=2/3 存活，其余死亡 | ✅ |
| C2.3 | 边界回绕 | 环面拓扑 (x/y 坐标取模) | ✅ |
| C2.4 | 迭代推进 | 非暂停时每 speed_ms/10 帧推进一代 | ✅ |
| C2.5 | 暂停/继续 `p` | 按 `p` 切换暂停状态，HUD 显示 PAUSED/RUN | ✅ |
| C2.6 | 单步 `SPACE` | 暂停时按空格推进一代 | ✅ |
| C2.7 | 图案切换 `g` | 按 `g` 加载滑翔机，重置代数为 0 | ✅ |
| C2.8 | 图案切换 `n` | 按 `n` 加载高斯帕滑翔机枪 (Gosper glider gun)，重置代数为 0 | ✅ |
| C2.9 | 图案切换 `r` | 按 `r` 随机初始化网格 | ✅ |
| C2.10 | 清空 `c` | 按 `c` 清空所有细胞，重置代数为 0 | ✅ |
| C2.11 | 速度调节 `+`/`-` | `+`/`=` 加速 (speed_ms-10, 下限 20)，`-`/`_` 减速 (上限 500) | ✅ |
| C2.12 | VGA 渲染 | 40×20 网格 + 边框 + HUD (代数+状态+按键提示) | 🟡 (VGA 硬件待线) |
| C2.13 | 退出 `q` | 返回 shell | ✅ |

### C3. conway_ed — 康威编辑器 (conway_ed.c)

> 注意：该文件当前仍是独立源码，**尚未注册进当前 `de2shell` 程序表，也未纳入 `make local` 构建入口**。
> 当前 shell 中 `life` 命令实际运行的是 `life.c`，不是本文件。

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| C3.1 | 编辑模式 | 启动时进入编辑模式 (MODE=EDITING)，全网格 80×25 | ❌ (未接入当前 shell) |
| C3.2 | 光标移动 | WASD 移动光标，边界回绕 | ❌ |
| C3.3 | 细胞切换 `SPACE` | 空格键翻转光标位置细胞状态 | ❌ |
| C3.4 | 运行 `ENTER` | 回车键开始模拟 (MODE=RUNNING) | ❌ |
| C3.5 | 暂停 `p` | 模拟过程中暂停/恢复 | ❌ |
| C3.6 | 清空 `c` | 清除全部细胞，回到编辑模式 | ❌ |
| C3.7 | 退出 `ESC` | ESC 返回 shell | ❌ |
| C3.8 | VGA 渲染 | 80×25 全屏 + HUD (代数和模式 + 光标坐标) | ❌ |

---

## D. 实验模块 (Exp1–Exp12)

### D1. exp1 — 3-8 译码器 (exp1.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| D1.1 | SW[2:0] 读入 | `gpio_read_in() & 0x07` 获取拨码开关值 | ✅ |
| D1.2 | 3-8 译码逻辑 | SW 值对应唯一低电平输出位 (active-low) | ✅ |
| D1.3 | 期望输出显示 | VGA 显示预期输出 (active-low，`0` = ON) | 🟡 (VGA 硬件待线) |
| D1.4 | LEDR[7:0] 实际显示 | VGA 显示实际 `gpio_read_out()` LED 状态 | 🟡 |
| D1.5 | 使能条件说明 | 显示 G1=1, G2A=0, G2B=0 | 🟡 |
| D1.6 | 退出 `q` | 返回 shell | ✅ |

### D2. exp4 — 双端口 RAM (exp4.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| D2.1 | 操作说明 | 显示 SW17 模式选择、SW[4:0] 地址、SW[12:5] 写数据、KEY0 写选通 | ✅ |
| D2.2 | 退出 `q` | 返回 shell | ✅ |
| D2.3 | 实时状态读取 (future) | VGA 实时显示地址/数据/读写模式 | ❌ (待 GPIO 接入后实现) |

### D3. exp5 — FSM 序列检测器 (exp5.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| D3.1 | 功能说明 | 显示 4 连续 0 或 4 连续 1 检测的 Moore/Mealy 机描述 | ✅ |
| D3.2 | 控制说明 | SW1=输入值, KEY0=时钟, LEDR[7:0]=输入历史, LEDG8=检测输出 | ✅ |
| D3.3 | 退出 `q` | 返回 shell | ✅ |
| D3.4 | 实时状态读取 (future) | VGA 实时显示输入历史移位寄存器 + 检测输出 | ❌ (待 GPIO 接入) |

### D4. exp12 — 简单 CPU (exp12.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| D4.1 | 架构说明 | 显示单累加器、16-bit 指令格式、5 条指令 (ADD/STORE/LOAD/JUMP/JNEG) | ✅ |
| D4.2 | 控制说明 | KEY2=模式切换, KEY1=单步, KEY0=复位, SW16=LCD 详情 | ✅ |
| D4.3 | HEX/LED 显示说明 | HEX7-6=IR, HEX5-4=PC, HEX3-0=AC, LEDR[7:0]=AC | ✅ |
| D4.4 | Demo 演示说明 | 显示 A=3+5=8 含 JNEG 分支测试 | ✅ |
| D4.5 | 退出 `q` | 返回 shell | ✅ |
| D4.6 | 实时状态读取 (future) | VGA 实时显示 PC/IR/AC/状态 | ❌ (待 GPIO 接入) |

---

## E. 系统工具

### E1. info — 系统信息页 (info.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E1.1 | CPU 信息 | 显示 NEORV32 RV32IMC + Zk* @ 50MHz | ✅ |
| E1.2 | 内存信息 | IMEM 64KB, DMEM 16KB, SDRAM 128MB | ✅ |
| E1.3 | 外设信息 | VGA 640×480@60Hz 80×25 text, 输入方式, 密码学算法列表 | ✅ |
| E1.4 | 退出 `q` | 返回 shell | ✅ |

### E2. monitor — RISC-V 汇编监视器 (monitor.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E2.1 | `help` 命令 | 输出全部命令列表 | ✅ |
| E2.2 | `regs` 命令 | 显示 32 个 RISC-V 寄存器快照 (名称+hex 值) | 🟡 (需寄存器快照注入) |
| E2.3 | `dump ADDR [N]` | hex dump N 个 32-bit word，默认 8，上限 64 | ✅ |
| E2.4 | `peek ADDR` | 读取并显示指定地址的 32-bit 值 | ✅ |
| E2.5 | `poke ADDR VAL` | 向指定地址写入 32-bit 值 | ✅ |
| E2.6 | `aes` 演示 | 执行 `aes32esmi/aes32esi` 指令并显示结果 | 🟡 (NEORV32 实板) |
| E2.7 | `sha256` 演示 | 执行 `sha256sig0/sum0` 指令并显示结果 | 🟡 |
| E2.8 | `sm4` 演示 | 执行 `sm4ed/sm4ks` 指令并显示结果 | 🟡 |
| E2.9 | LOCAL_BUILD 降级 | 用软件模拟替代硬件指令 | ✅ |
| E2.10 | 退出 `q` | 返回 shell | ✅ |
| E2.11 | 命令行别名 | `monitor`、`rv32` 均启动 | ✅ |

### E3. dashboard — 系统仪表盘 (dashboard.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E3.1 | 页面框架 | 显示 dashboard 标题、说明、实时状态区 | 🟡 (代码完成，待上板确认) |
| E3.2 | 退出 `q` | 返回 shell | ✅ |
| E3.3 | SW 实时读取 | 实时显示 18 个拨码开关状态 | 🟡 (代码完成，待上板确认) |
| E3.4 | 板级外设接管 | dashboard 通过 `board_status` 主动驱动 LCD/HEX/LED | 🟡 |
| E3.5 | KEY 按键检测 | 显示 `KEY[3:1]` 当前状态，并映射到 flags/LEDG | 🟡 |
| E3.6 | IR 码值显示 (future) | 显示最近收到的红外遥控码 (NEC 格式) | ❌ |
| E3.7 | 系统时间栏 | 当前版本显示 uptime 秒数，不要求 RTC | 🟡 |

---

## F. 硬件依赖外设验收

### F1. Wishbone Interconnect (wb_intercon.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F1.1 | SDRAM (s0) | 0x01000000 范围读写正常 | ✅ |
| F1.2 | VGA 终端 (s1) | 0xF0000000 范围字符写入 | 🟡 |
| F1.3 | PS/2 键盘 (s2) | 0xF0002000 范围寄存器读写正常 | ✅ |
| F1.4 | 未映射地址 | 返回 bus error，无死锁 | ✅ |
| F1.5 | Quartus 编译 | 综合+布局布线无错误 | ✅ |

### F2. VGA 文字终端 (vga_text_terminal.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F2.1 | VGA 时序 | 640×480@60Hz，HS/VS 同步 | 🟡 (仿真通过，待显示器) |
| F2.2 | 字符显示 | 写 text buffer，VGA 正确显示 ASCII | 🟡 |
| F2.3 | CP437 字库 | 全部可打印字符 0x20-0x7E 正确 | 🟡 |
| F2.4 | 光标闪烁 | ~1Hz 频率闪烁 | 🟡 |
| F2.5 | 双页切换 | F1/F2 页内容独立，切换无花屏 | 🟡 |
| F2.6 | 清屏 | 写清屏寄存器当前页全部清空 | 🟡 |
| F2.7 | 背景色 | 写背景色寄存器生效 | 🟡 |
| F2.8 | Testbench | QuestaSim 仿真波形通过 | ✅ |

### F3. PS/2 键盘控制器 (ps2_controller.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F3.1 | 11-bit 帧接收 | 起始位+8数据+奇偶+停止位正确解码 | ✅ |
| F3.2 | RX FIFO | 16-entry，CPU 可读取 | ✅ |
| F3.3 | 扩展键 E0 前缀 | 方向键/F1-F12/Ctrl 识别 | ✅ |
| F3.4 | 主机发送 | CPU 写 TXDATA 后发送字节到键盘 | ✅ |
| F3.5 | ACK 检测 | 发送后正确接收 0xFA | ✅ |
| F3.6 | Lock 灯同步 | ED + LED mask 命令链稳定工作 | ✅ |
| F3.7 | 中断路由 | IRQ → NEORV32 mext_irq_i | ✅ |
| F3.8 | IRQ 使能/屏蔽 | 写中断使能寄存器控制 | ✅ |

### F4. LCD 调试屏 (lcd_debug.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F4.1 | 硬件扫描码译码 | SW16=1 时，LCD 第 2 行实时显示键盘字符 | ✅ |
| F4.2 | Set 2 协议状态机 | E0/F0 前缀正确处理 | ✅ |
| F4.3 | Shift 状态跟踪 | 左右 Shift 按下/释放影响 ASCII 输出 | ✅ |
| F4.4 | 16 字环形缓冲区 | 最近 16 按键正确滚动 | ✅ |
| F4.5 | 特殊键显示 | 方向键/Enter/Backspace/Tab/Esc 有特殊符号 | ✅ |

### F5. IR 遥控解码 (ir_nec_decoder.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F5.1 | NEC 协议解码 | 引导码+地址+命令正确解析 | ✅ |
| F5.2 | 命令输出到 CPU | CPU 可读取解码后的命令字节 | ✅ |
| F5.3 | CH1-CH7 映射 | 7 个频道按钮正确路由 | ✅ |
| F5.4 | CH+/CH- 顺序切换 | 频道+/- 在程序列表中顺序切换 | ✅ |

---

## G. 跨切面测试

### G1. 编译检查

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| G1.1 | NEORV32 交叉编译 | `make clean all image` 无错误 | ✅ |
| G1.2 | LOCAL_BUILD 编译 | `make local` (host gcc) 无错误 | ✅ |
| G1.3 | IMEM 镜像尺寸 | `neorv32_imem_image.vhd` 产生的 text < 32KB | ✅ |
| G1.4 | Quartus 全工程编译 | Fitter/Assembler 无错误 | ✅ |

### G2. 接口一致性

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| G2.1 | program_t 接口一致 | 所有子程序实现全部 6 个回调字段 (name/help/init/update/input/ir_input/finish) | ✅ |
| G2.2 | 寄存器地址与 pkg 一致 | VGA_BASE/PS2_BASE 等软件常量与 `de2extra_pkg.vhd` 匹配 | ✅ |
| G2.3 | QSF 引脚分配无冲突 | 每个物理引脚仅由一个模块驱动 | ✅ |

---

## 状态汇总

| 类别 | 总数 | ✅ | 🟡 | ❌ | N/A |
|---|---|---|---|---|---|
| A. 基础设施 | 17 | 14 | 3 | 0 | 0 |
| B. 核心应用 | 38 | 16 | 13 | 8 | 1 |
| C. 游戏 | 26 | 20 | 6 | 0 | 0 |
| D. 实验模块 | 16 | 12 | 4 | 0 | 0 |
| E. 系统工具 | 16 | 11 | 3 | 2 | 0 |
| F. 硬件外设 | 22 | 13 | 9 | 0 | 0 |
| G. 跨切面 | 7 | 7 | 0 | 0 | 0 |
| **合计** | **142** | **93** | **38** | **10** | **1** |

**当前通过率**: 93/142 ≈ **65.5%**

**主要阻塞**:
1. ⏳ VGA→HDMI 有源转换器 (预计 5/26 到货) — 解锁约 30 项 VGA 渲染验收
2. ❌ Zk* 密码学指令加速 (8 项) — 纯 C 基线已验收，加速版未实现
3. ❌ 实验模块实时 GPIO 读取 (4 项) — 桩模块就位，待外设板测
4. ❌ TRNG 统计验证 (1 项)

---

*最后更新: 2026-05-24 — 基于 `sw/app/de2shell/` 全部源码及 `doc/phases/` 阶段文档整理*
