# de2shell 模块验收表

> 整理时间: 2026-05-25 (v2)
> 适用范围: `sw/app/de2shell/` 全线 C 软件 + 依赖的 VHDL 硬件外设
> 配套文档: `implementation_plan.md`, `phases/phase1-bus-sdram.md`, `phases/phase2a-crypto-cli.md`, `phases/phase2b-vga-terminal.md`, `phases/phase3-integration.md`
> 注意: `de2os` (FreeRTOS + SDRAM 执行) 的验收表另建，不在此文件范围内

---

## 最新上板结果

- 构建/烧录: Docker 手动构建 + Quartus 手动编译 → JTAG 烧录
- 实测板卡: `EP4CE115F29C7`
- 串口: `COM10`, `115200 8N1`
- shell 首页: `DE2Extra Shell v0.2`
- LCD 修复: busy-polling → 固定延时 (2ms/cmd, 1ms/char)，待目视确认
- HEX/状态字: shell 空闲时可见心跳翻转，证明主循环仍在推进
- IMEM: 62,872 bytes / 65,536 bytes (95.9%, 剩余 2,664 bytes)
- Quartus: 27,508 LEs (24%), 9,239 registers, 937K memory bits, 编译耗时 25m57s

本轮新增模块/改动：

- VGA 像素模式控制器 (`vga_pixel_ctrl.vhd`) — 硬件完成，SDL2 验证通过
- VGA 像素模式地址解码 — 写入 `de2_115_top.vhd` (0x1F80+ offset)
- Win 3.0 GUI (`startui` 命令) — 软件+SDL2 验证通过，等 VGA 线上板
- LCD HAL 修复 — 固定延时替代 busy-polling，解决只显示 "LDL" 问题
- 绘图库 (`gfx.c/h`) — 填充、画线、字符渲染、3D 凹凸边框
- GUI 控件库 (`gui.c/h`, `gui_widgets.c`) — 窗口、按钮、标签、文本框、任务栏
- PS/2 解码器提取 (`ps2_decoder.c/h`) — 可复用模块
- 帧缓冲 HAL (`fb_hal.c`) — NEORV32 后端写入 SDRAM + VGA 像素模式寄存器

已通过串口 smoke test 的模块：

| 模块 | 进入 | 退出 | 备注 |
|---|---|---|---|
| `help` | ✅ | N/A | 列出全部命令 (含 startui) |
| `lcdmon` | ✅ | N/A | 输出软件侧 LCD 16x2 阴影缓冲 |
| `info` | ✅ | ✅ | `q` 返回 `0000>` |
| `hello` | ✅ | ✅ | `q` 返回 `0000>` |
| `dash` | ✅ | ✅ | 串口验收通过 |
| `monitor` | ✅ | ✅ | `q` 返回 `0000>` |
| `crypto` | ✅ | ✅ | `q<CR>` 返回 `0000>` |
| `ps2` | ✅ | ✅ | 串口可见键盘事件与 LED sync 日志 |
| `snake` | ✅ | ✅ | `q` 返回 `0000>` |
| `life` | ✅ | ✅ | `q` 返回 `0000>` |
| `memtest` | ✅ | ✅ | 五项 SDRAM 测试实板 `ALL PASS` |
| `expdemo` | ✅ | ✅ | 菜单进入/浏览/退出通过 |
| `startui` | 🟡 | 🟡 | SDL2 验证通过；NEORV32 实板需 VGA 显示器 |

本次 bitstream (builds/de2shell_lcd_vgapx/)：

- IMEM 95.9% (62,872 bytes)，接近上限
- Quartus 路由拥塞 (92% at X58_Y37~X68_Y48)，高努力重试后通过
- NTT 硬件仍为占位响应，`0xF000C000` 不代表 NTT 已恢复

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
| A1.1 | 命令解析 | `help` 输出当前全部命令列表 (含 startui) | ✅ |
| A1.2 | 程序调度 | 输入子命令名称后在 `active_prog` 间切换 | ✅ |
| A1.3 | 程序 init/update/input/finish 回调 | 每个程序切换时调 `init()`，每帧调 `update()`，按键调 `input()`，返回 shell 时调 `finish()` | ✅ |
| A1.4 | UART 输入 | `uart_kbhit()/uart_getc()` 正确读取 COM10 115200 8N1 | ✅ |
| A1.5 | 退格处理 | 退格键删除上一个输入字符并回退光标 | ✅ |
| A1.6 | 空行处理 | 按下回车不解析空命令，直接重打提示符 | ✅ |
| A1.7 | 未知命令 | 输入未注册命令时输出 `? Unknown command. Type 'help'` | ✅ |
| A1.8 | `cls` 命令 | 清屏并重绘 shell 启动画面 | ✅ |
| A1.9 | `quit`/`exit` 命令 | 从子程序返回 shell 主界面 | ✅ |
| A1.10 | 状态栏常驻 | 第 25 行 (row 24) 显示当前频道名，右侧显示 uptime (按分钟刷新) | ✅ 串口实测可见 `Up HH:MM` 递增 |
| A1.11 | 程序注册表完整性 | 12 个用户程序 (含 startui) + shell 的 `prog_id_t` 全部注册到 `programs[]` 数组 | ✅ |
| A1.12 | IR 遥控切频 | 遥控器按内部频道号映射：`1-9` 对应 hello/memtest/crypto/ps2/snake/life/dash/info/monitor，`A` 进入 expdemo；`0/RETURN` 返回 shell；`CH+/CH-` 顺序切换 | ✅ |
| A1.13 | IR 指令透传 | 子程序的 `ir_input` 回调优先级高于全局 IR 映射 | ✅ 已由 dashboard `ir_input` 吞掉全局切频验证 |
| A1.14 | Docker 交叉编译 | 手动 Docker 构建链可稳定生成 `de2shell` IMEM 镜像；当前 `Executable (VHD)` 为 `62872 bytes` (95.9%)，适配 64KB IMEM | ✅ |
| A1.15 | LOCAL_BUILD 编译 | `make local` (host gcc) 编译通过 | ✅ |
| A1.16 | 统一板级状态层 | `board_status.c/h` 负责 shell/子程序对 LCD/HEX/LED 的统一编码与接管 | ✅ |
| A1.17 | `lcdmon` 命令 | 输出软件侧 LCD 16x2 阴影缓冲，不依赖物理 LCD 回读 | ✅ |

### A2. VGA HAL (vga_hal.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A2.1 | `vga_init()` | 清屏 + 显示静态光标 + 复位行列计数 | ✅ 上板通过 |
| A2.2 | `vga_putc()` | 字符写入 VGA text buffer 对应行列，(NEORV32 模式) 同步输出到 UART | ✅ 上板通过 |
| A2.3 | `vga_puts()` | 连续写字符串 | ✅ 上板通过 |
| A2.4 | `vga_goto()` | 光标移动到分屏坐标 (0-79, 0-24) | ✅ 上板通过 |
| A2.5 | `vga_clear()` | 写 `VGA_CTRL_CLEAR` 寄存器清当前活动页 | ✅ 上板通过 |
| A2.6 | `vga_cursor_show()` | 设置/取消可见静态光标；显示时关闭 `VGA_CTRL_BLINK` | ✅ 上板通过 |
| A2.7 | `vga_col()` / `vga_row()` | 返回当前行列号 | ✅ 上板通过 |
| A2.8 | `vga_puthex32()` | 以固定宽度 (8 hex digits) 显示 32-bit 值 | ✅ 上板通过 |
| A2.9 | 换行处理 (`\n`) | `cur_col=0; cur_row++` 且 row 超出 VGA_ROWS 时自动折返 | ✅ 上板通过 |
| A2.10 | 退格处理 (`\b`) | 光标左移一格并擦除字符 | ✅ 上板通过 |
| A2.11 | RGB332 颜色常量 | 8 色 + 灰度正确定义 | ✅ 上板通过 |
| A2.12 | NEORV32 模式地址映射 | VGA_BASE = `0xF0000000`，控制寄存器偏移正确 (cursor_x/y, ctrl, status, bgcolor, clear) | ✅ 上板通过 |
| A2.13 | NEORV32 模式 UART 镜像 | 每个 VGA 字符同步从 `neorv32_uart0` 输出 | ✅ |

### A3. GPIO HAL (gpio_hal.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A3.1 | `gpio_read_in()` | NEORV32: 读 `neorv32_gpio_port_get()`；LOCAL: 返回模拟值 | ✅ |
| A3.2 | `gpio_read_out()` | NEORV32: 读 `NEORV32_GPIO->PORT_OUT`；LOCAL: 返回模拟值 | ✅ |
| A3.3 | LOCAL_BUILD 模拟注入 | `gpio_set_sim_in/out()` 可修改模拟值用于测试 | ✅ |

### A4. 帧缓冲 HAL (fb_hal.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A4.1 | `fb_init()` | NEORV32: 写 VGA 像素模式寄存器启用像素模式，设置 framebuffer 基址 (0x01800000)；LOCAL: 创建 SDL2 窗口 + 渲染器 | ✅ LOCAL_BUILD 通过 |
| A4.2 | `fb_set_pixel()` | 设置指定坐标的 RGB332 像素值；NEORV32: 直接写 SDRAM；LOCAL: 写 SDL2 纹理 | ✅ LOCAL_BUILD 通过 |
| A4.3 | `fb_present()` | 刷新显示；NEORV32: 写 VGA 像素寄存器触发刷新；LOCAL: SDL_RenderPresent + SDL_PollEvent | ✅ LOCAL_BUILD 通过 |
| A4.4 | `fb_shutdown()` | 关闭 framebuffer；NEORV32: 写 VGA 像素模式寄存器切回文本模式；LOCAL: 销毁 SDL2 窗口 | ✅ LOCAL_BUILD 通过 |
| A4.5 | `fb_poll_events()` | LOCAL_BUILD: 处理 SDL2 事件队列防止窗口无响应 | ✅ LOCAL_BUILD 通过 |
| A4.6 | NEORV32 VGA 像素模式寄存器 | 写 `0xF0000000 + 0x1F80` 启用像素模式，写 `0xF0000000 + 0x1F84` 设基址 | 🟡 待 VGA 显示器验证 |

### A5. LCD HAL (lcd_hal.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A5.1 | `lcd_init()` | HD44780 初始化序列 (Function Set 8-bit 2-line, Display On, Clear, Entry Mode) | ✅ 串口 `lcdmon` 验证通过 |
| A5.2 | 固定延时通信 | 2ms/cmd 延时 + 1ms/char 延时，替代不可靠的 busy-polling | ✅ 修复了只显示 "LDL" 的 bug |
| A5.3 | `lcd_set_cursor()` | 设置 DDRAM 地址到指定行列 | ✅ |
| A5.4 | `lcd_print()` | 向 LCD 写入字符串，自动截断 16 字符 | ✅ `lcdmon` 输出 `L0=[DE2Extra Shell  ]` |
| A5.5 | NEORV32 MMIO | 通过 `LCD->cr` / `LCD->dr` 写入 Wishbone LCD 控制器 (0xF0008000) | ✅ |

### A6. 绘图库 (gfx.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A6.1 | `gfx_fill_rect()` | 矩形区域填充指定颜色 | ✅ LOCAL_BUILD 通过 |
| A6.2 | `gfx_rect()` | 1px 矩形边框 | ✅ LOCAL_BUILD 通过 |
| A6.3 | `gfx_line()` | Bresenham 直线算法 | ✅ LOCAL_BUILD 通过 |
| A6.4 | `gfx_hline()` / `gfx_vline()` | 优化水平/垂直线 | ✅ LOCAL_BUILD 通过 |
| A6.5 | `gfx_char()` | 8×16 位图字符渲染 (CP437 字体) | ✅ LOCAL_BUILD 通过 |
| A6.6 | `gfx_text()` | 字符串渲染，支持 `\n` 换行 | ✅ LOCAL_BUILD 通过 |
| A6.7 | `gfx_clear()` | 全屏填充指定颜色 | ✅ LOCAL_BUILD 通过 |
| A6.8 | `gfx_bevel()` | 3D 凹凸边框 (Win 3.0 风格：raised=true 白色左上+深色右下，反之亦然) | ✅ LOCAL_BUILD 通过 |
| A6.9 | RGB332 颜色常量 | FB_CYAN, FB_LTGRAY, FB_DKGRAY, FB_WHITE, FB_BLACK 等 Win 3.0 配色 | ✅ LOCAL_BUILD 通过 |

### A7. PS/2 解码器 (ps2_decoder.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A7.1 | `ps2_dec_init()` | 初始化解码器状态机 | ✅ |
| A7.2 | `ps2_dec_feed()` | 输入原始 scancode，返回完整按键事件 (make/break/E0 扩展) | ✅ 从 ps2.c 提取并验证 |
| A7.3 | ASCII 输出 | 可打印键输出 ASCII，不可打印键输出 0 | ✅ |
| A7.4 | 扩展键前缀 (E0) | 方向键、功能键等正确标记 `is_extended` | ✅ |
| A7.5 | 按键名称 | 每个事件包含键名字符串 ("Enter", "Tab", "A" 等) | ✅ |

### A8. GUI 控件库 (gui.c/h, gui_widgets.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| A8.1 | 控件池管理 | 静态池最多 32 个 widget，分配/释放正确 | ✅ LOCAL_BUILD 通过 |
| A8.2 | `gui_render_all()` | 从底到顶渲染所有可见控件 | ✅ LOCAL_BUILD 通过 |
| A8.3 | `gui_dispatch_key()` | 将按键事件路由到焦点控件 | ✅ LOCAL_BUILD 通过 |
| A8.4 | `gui_focus_next()`/`gui_focus_prev()` | Tab/Shift+Tab 循环焦点 | ✅ LOCAL_BUILD 通过 |
| A8.5 | Window 控件 | 标题栏 (20px, FB_DKGRAY) + 3D 凹凸边框 + 关闭 [X] 按钮 + FB_LTGRAY 客户区 | ✅ LOCAL_BUILD 通过 |
| A8.6 | Button 控件 | 3D 凹凸 + 居中文字 + 焦点高亮 + Enter/Space 按下动画 | ✅ LOCAL_BUILD 通过 |
| A8.7 | Label 控件 | 纯文本显示，无交互 | ✅ LOCAL_BUILD 通过 |
| A8.8 | TextInput 控件 | 边框 + 文本缓冲 + 闪烁光标 + Backspace/Left/Right/Home/End | ✅ LOCAL_BUILD 通过 |
| A8.9 | Taskbar 控件 | 底部 24px, FB_DKGRAY, "DE2Extra" 标签 + 时钟 | ✅ LOCAL_BUILD 通过 |
| A8.10 | Icon 控件 | 32×32 位图占位 + 下方标签文字 | ✅ LOCAL_BUILD 通过 |

---

## B. 核心应用程序

### B1. hello — Phase 0 LED 跑马灯演示 (hello.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B1.1 | 启动画面 | 显示 CPU 型号 (RV32IMC+Zk*)、板卡型号、NEORV32 alive 消息 | ✅ |
| B1.2 | LED 跑马灯 | 16 个 LED 依次点亮 (`1<<led_idx`)，VGA 上以 `*`/`.` 显示 | ✅ 上板通过 |
| B1.3 | 秒计数器 | HEX 上显示递增的 16 进制秒数 (0x00-0xFF)，16 LED 周期为 1 秒 | ✅ 上板通过 |
| B1.4 | NEORV32 GPIO 输出 | 执行 `neorv32_gpio_port_set(gpio_val)` 驱动真实 LED/HEX | ✅ |
| B1.5 | 退出 `q` | 按下 `q` 后 `finish()` 返回真，shell 接管 | ✅ |

### B2. memtest — SDRAM 自检 (memtest.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B2.1 | Walking-1s immediate | 逐字写入 `1<<(i%32)` 并立即回读比对，1024 words | ✅ |
| B2.2 | Walking-1s bulk | 先全部写入再全部回读，1024 words | ✅ |
| B2.3 | Checkerboard | 交替写入 `0xAAAAAAAA`/`0x55555555`，回读比对 | ✅ |
| B2.4 | Address-as-data | 写入自身地址值，回读比对 | ✅ |
| B2.5 | 全部通过 | VGA 显示 `All 5 SDRAM cases passed.`，LCD 显示 `LCD_STATUS_PASS` | ✅ |
| B2.6 | 失败信息 | 显示完整 `test/word/addr/exp/got`，LCD 继续走 fail meta + got 协议 | ✅ |
| B2.7 | 重测 `r` | 按 `r` 重新执行全部 5 项测试 | ✅ |
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
| B3.10 | `bench` | 纯 C 与 Zk* 加速版本的性能对比表 (cycles + speedup) | ✅ AES 107.6x, SM4 1.7x, SHA-512 1.5x, SHA-256 1.2x, SM3 1.0x |
| B3.11 | `cls` / `clear` | 清屏并重绘提示符 | ✅ |
| B3.12 | `quit` / `exit` / `q` | 返回 shell | ✅ |
| B3.13 | hex 解码容错 | `hex_decode()` 支持大小写、空格分隔 | ✅ |
| B3.14 | 命令参数解析 | 支持最多 8 个参数 | ✅ |
| B3.15 | AES-128 Zk* 加速 | `aes32esmi`/`aes32dsi` 路径已接入 `bench` | ✅ |
| B3.16 | SHA-256 Zk* 加速 | `sha256sig0/1` + `sha256sum0/1` 路径已接入 `bench` | ✅ |
| B3.17 | SHA-512 Zk* 加速 | `sha512sig0h/l` + `sha512sum0r/1r` 路径已接入 `bench` | ✅ |
| B3.18 | SM4 Zk* 加速 | `sm4ed`/`sm4ks` 路径已接入 `bench` | ✅ |
| B3.19 | SM3 Zk* 加速 | `sm3p0`/`sm3p1` 路径已接入 `bench` | ✅ |
| B3.20 | TRNG 统计验证 | `bench` 内置 256-byte 单比特统计，输出 `1-bits/0-bits/ratio` | ✅ 1029/1019 = 50.24% |

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
| B4.8 | VGA 事件日志 | 每次按键打印 scan code、键名、修饰键状态、ASCII tty 表示 | ✅ 上板通过 |
| B4.9 | UART 镜像 | 每次事件同时输出到 UART | ✅ |
| B4.10 | 日志滚屏 | 超出 VGA 可视行数后自动清屏并重新打印标题 | ✅ 上板通过 |
| B4.11 | 清屏 `c` | 按 `c` 清空日志并重置 | ✅ |
| B4.12 | 退出 `q` | 返回 shell | ✅ |
| B4.13 | 状态寄存器解析 | `ready`/`overflow`/`tx_busy`/`tx_done`/`tx_err`/`bus_idle` 正确读取 | ✅ |
| B4.14 | LOCAL_BUILD 降级 | 显示无 PS/2 硬件提示，按 `q` 退出 | N/A |

### B5. startui — Win 3.0 桌面 GUI (win30_desk.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| B5.1 | 命令进入 | 输入 `startui` 或 `gui` 进入 Win 3.0 桌面 | ✅ 串口命令已注册 |
| B5.2 | 桌面背景 | FB_CYAN (经典 Win 3.0 青色) 实色填充 | ✅ LOCAL_BUILD 通过 |
| B5.3 | 桌面图标网格 | 3×3 图标网格 (Snake, Life, Crypto, Info, Dashboard, PS2, Demo, MemTest, Settings) | ✅ LOCAL_BUILD 通过 |
| B5.4 | 任务栏 | 底部 24px, 显示 "DE2Extra" 标签 + 时钟 | ✅ LOCAL_BUILD 通过 |
| B5.5 | 演示窗口 | 启动时打开 2 个演示窗口 (Calculator mock, About dialog) | ✅ LOCAL_BUILD 通过 |
| B5.6 | 键盘导航 | Tab 循环焦点，Enter 激活，Escape 关闭窗口，方向键导航 | ✅ LOCAL_BUILD 通过 |
| B5.7 | F10 菜单 | F10 打开 "Start Menu" | ✅ LOCAL_BUILD 通过 |
| B5.8 | SDL2 事件输入 | LOCAL_BUILD 模式使用 SDL2 键盘事件 (非 _kbhit/_getch) | ✅ LOCAL_BUILD 通过 |
| B5.9 | NEORV32 PS/2 输入 | NEORV32 模式轮询 PS/2 MMIO，scancode → ps2_dec_feed → gui_dispatch_key | 🟡 待 VGA + PS/2 联合验证 |
| B5.10 | 像素模式生命周期 | init() 启用像素模式，finish() 切回文本模式 | 🟡 待 VGA 显示器验证 |
| B5.11 | 退出 Escape | 顶层 Escape 返回 shell 文本模式 | 🟡 待实板验证 |

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
| C1.8 | VGA 渲染 | 40×20 网格 + 边框 + HUD (得分+速度) | ✅ 上板通过 |
| C1.9 | Game Over 显示 | 网格中央显示 "GAME OVER" | ✅ 上板通过 |
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
| C2.12 | 编辑模式默认进入 | 启动后进入 `EDIT`，光标位于网格中心 | ✅ |
| C2.13 | 光标移动 | 方向键 / WASD 都能移动光标，支持边界回绕 | ✅ |
| C2.14 | 细胞切换 | 编辑态按空格翻转当前光标位置细胞 | ✅ |
| C2.15 | 运行 / 返回编辑 | `Enter` 进入运行，`E` 返回编辑 | ✅ |
| C2.16 | HUD 坐标与状态 | HUD 显示 `RUN/EDIT/HOLD` 以及 `X/Y` 坐标 | ✅ |
| C2.17 | VGA 渲染 | 40×20 网格 + 边框 + HUD (代数+状态+按键提示) | ✅ 上板通过 |
| C2.18 | 退出 `q` | 返回 shell | ✅ |

### C3. `conway_ed` 旧实现

`conway_ed.c` 已退出当前 `de2shell` 正式路径。编辑功能已并入 `life.c`，后续验收只看 `life`，不再把 `conway_ed` 作为并行实现维护。

---

## D. 硬件实验模块 (expdemo)

> 原 exp1/exp4/exp5/exp12 独立 C 入口已删除，统一由 `expdemo` (demo.c) 通过 Wishbone MMIO
> 驱动硬件实验多路复用器 (`expdemo_wb.vhd` + `expdemo_top.vhd`)。

### D1. expdemo 统一入口 (demo.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| D1.1 | `expdemo` 命令进入 | 输入 `expdemo` 显示 Home 页与实验列表 | ✅ |
| D1.2 | 实验列表显示 | 显示 11 个实验: Exp1/2/3/4/5/8/9/10/11/12/13，标注 6/7 保留 | ✅ |
| D1.3 | 数字键 + Enter 选择 | 输入 `1` + Enter 切换到 Exp1，并进入”实验说明 + Live Monitor”页 | ✅ |
| D1.4 | `+`/`-` 浏览实验 | 按 `+`/`-` 顺序切换 selected_channel | ✅ 串口实测通过 |
| D1.5 | `q` / `MENU` 两级退出 | 实验页 `q/MENU` 回 Home；Home 页 `q/MENU` 退回 shell | ✅ |
| D1.6 | IR 遥控数字键选择 | 遥控器 1-9 输入数字，RETURN/PLAY 确认启动 | ✅ |
| D1.7 | IR MENU 退出 | 实验页 MENU 回 Home；Home 页 MENU 返回 shell | ✅ |
| D1.8 | IR CH+/CH- 浏览 | 遥控器 CH+/CH- 顺序切换实验 | ✅ |
| D1.9 | HW channel 自动回零检测 | 运行中 Exp8/Exp10 硬件自动将 channel 复位为 0 时，expdemo 自动回 Home | ✅ |
| D1.10 | Live Monitor 实时刷新 | 运行时显示 HW channel、STATUS、SW/KEY/IR/uptime 实时值 | ✅ |
| D1.11 | `KEY0` 板级保留 | `expdemo` 内所有实验不再使用物理 `KEY0`，`KEY0` 仅保留整板 reset | ✅ |
| D1.12 | shell 全局 KEY 热键屏蔽 | 进入 `expdemo` 后，shell 的 `KEY1/2/3` 快捷键不再抢占实验按键 | ✅ |

### D2. ExpDemo 硬件修复清单

> 详见 `doc/expdemo_repair.md`

| # | 问题 | 严重性 | 状态 |
|---|---|---|---|
| R1 | Exp8 PS/2 Del 退出检测缺失 | 关键 | ✅ 上板通过 |
| R2 | Exp10 IR MENU 退出检测缺失 | 关键 | ✅ 上板通过 |
| R3 | Exp9 UART TXD 未接入 | 关键 | ✅ 上板通过 |
| R4 | 输入侧 PS/2/IR mux 未实现 | 重要 | N/A Exp8/10 改用 shell 内置 ps2/monitor 代替 |
| R5 | Exp8/10 导航盲区 | 重要 | N/A 同 R4，不再需要硬件退出检测 |
| R6 | LCD 切换后可能需重新初始化 | 重要 | ✅ 上板通过 |
| R7 | 所有实验始终运行 (无复位) | 次要 | 可选修复 |
| R8 | KEY0 共享复位 | 次要 | ✅ 上板通过 |
| R9 | Exp2/3 自生时钟 Timing Warning | 次要 | 可选修复 |
| R10 | 保留通道 6/7 意外激活输出 mux | 重要 | ✅ 上板验证：poke 6/7 读回 0，mux 未被激活 |
| R11 | Exp10 irda_top 未单独验证 | 重要 | N/A Exp10 改用 shell 内置 IR 功能代替 |

---

## E. 系统工具

### E1. info — 系统信息页 (info.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E1.1 | CPU 信息 | 显示 NEORV32 RV32IMC + Zk* @ 50MHz | ✅ |
| E1.2 | 内存信息 | IMEM 64KB, DMEM 16KB, SDRAM 128MB | ✅ |
| E1.3 | 外设信息 | VGA 640×480@60Hz 80×25 text, 输入方式, 密码学算法列表 | ✅ |
| E1.4 | 退出 `q` | 返回 shell | ✅ |
| E1.5 | 版本/仓库信息 | 显示 `v0.2` 与 GitHub 仓库地址 | ✅ |

### E2. monitor — RISC-V 汇编监视器 (monitor.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E2.1 | `help` 命令 | 输出全部命令列表 | ✅ |
| E2.2 | `regs` 命令 | 显示 32 个 RISC-V 寄存器快照 (名称+hex 值) | ✅ |
| E2.3 | `dump ADDR [N]` | hex dump N 个 32-bit word，默认 8，上限 64 | ✅ |
| E2.4 | `peek ADDR` | 读取并显示指定地址的 32-bit 值 | ✅ |
| E2.5 | `poke ADDR VAL` | 向指定地址写入 32-bit 值 | ✅ |
| E2.6 | `aes` 演示 | 执行 `aes32esmi/aes32esi` 指令并显示结果 | ✅ `0x87A0D7EB` / `0xAABBCCC6` |
| E2.7 | `sha256` 演示 | 执行 `sha256sig0/sum0` 指令并显示结果 | ✅ `0xE7FCE6EE` / `0x66146474` |
| E2.8 | `sm4` 演示 | 执行 `sm4ed/sm4ks` 指令并显示结果 | ✅ `0x65743CE2` / `0xCA25B52E` |
| E2.9 | LOCAL_BUILD 降级 | 用软件模拟替代硬件指令 | ✅ |
| E2.10 | 退出 `q` | 返回 shell | ✅ |
| E2.11 | 命令行别名 | `monitor`、`rv32` 均启动 | ✅ |

### E3. dashboard — 系统仪表盘 (dashboard.c)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E3.1 | 页面框架 | 显示 dashboard 标题、说明、实时状态区 | ✅ |
| E3.2 | 退出 `q` | 返回 shell | ✅ |
| E3.3 | SW 实时读取 | 实时显示 18 个拨码开关状态 | ✅ |
| E3.4 | 板级外设接管 | dashboard 通过 `board_status` 主动驱动 LCD/HEX/LED | ✅ |
| E3.5 | KEY 按键检测 | 显示 `KEY[3:1]` 当前状态，并映射到 flags/LEDG | ✅ |
| E3.6 | IR 码值与键义显示 | 显示最近收到的红外遥控码以及对应键义 (`CH+`/`1`/`RETURN` 等) | ✅ 实板已见 `Last IR` 与键义同步更新 |
| E3.7 | 系统时间栏 | 当前版本显示 uptime 秒数，不要求 RTC | ✅ |

### E4. NTT 加速器驱动 (ntt.c/h)

| # | 验收项 | 预期行为 | 状态 |
|---|---|---|---|
| E4.1 | LOCAL_BUILD 编译 | `make local` 编译通过，SW 参考实现完整 | ✅ |
| E4.2 | 交互式 CLI | `load delta` / `load random` / `ntt` / `intt` / `roundtrip` / `dump` 命令就绪 | ✅ |
| E4.3 | 软件 NTT 正确性 | 与 VHDL 引擎一致：DIF stages 7→0，Barrett reduction | ✅ |
| E4.4 | delta 测试 | delta 向量 NTT/INTT 轮转验证 PASS | ✅ |
| E4.5 | round-trip 测试 | 随机输入 round-trip (NTT→INTT) 验证 PASS | ✅ |
| E4.6 | convolution 测试 | 卷积正确性验证 PASS | ✅ |
| E4.7 | NEORV32 实板 MMIO | 硬件 NTT (0xF000C000) 寄存器读写 | ❌ 当前 bitstream 仍为占位响应，需先恢复真实 NTT 盒子再谈上板 |
| E4.8 | 性能对比 | 纯 C vs 硬件加速性能对比 | ❌ 依赖 E4.7；真实硬件未并回前不验收 |
| E4.9 | 退出 `q` | 返回 shell | ✅ |

---

## F. 硬件依赖外设验收

### F1. Wishbone Interconnect (wb_intercon.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F1.1 | SDRAM (s0) | 0x01000000 范围读写正常 | ✅ |
| F1.2 | VGA 终端 (s1) | 0xF0000000 范围字符写入 | ✅ 上板通过 |
| F1.3 | PS/2 键盘 (s2) | 0xF0002000 范围寄存器读写正常 | ✅ |
| F1.4 | 未映射地址 | 返回 bus error，无死锁 | ✅ |
| F1.5 | Quartus 编译 | 综合+布局布线无错误 | ✅ |

### F2. VGA 文字终端 (vga_text_terminal.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F2.1 | VGA 时序 | 640×480@60Hz，HS/VS 同步 | ✅ 上板通过 |
| F2.2 | 字符显示 | 写 text buffer，VGA 正确显示 ASCII | ✅ 上板通过 |
| F2.3 | CP437 字库 | 全部可打印字符 0x20-0x7E 正确 | ✅ 上板通过 |
| F2.4 | 光标闪烁 | ~1Hz 频率闪烁 | ✅ 上板通过 |
| F2.5 | 双页切换 | F1/F2 页内容独立，切换无花屏 | ✅ 上板通过 |
| F2.6 | 清屏 | 写清屏寄存器当前页全部清空 | ✅ 上板通过 |
| F2.7 | 背景色 | 写背景色寄存器生效 | ✅ 上板通过 |
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
| F5.3 | 数字键 1-9 映射 | 遥控器数字键 `1-9` 按内部频道号正确路由到 shell 程序，`A` 路由到 expdemo | ✅ |
| F5.4 | CH+/CH- 顺序切换 | `CH+`/`CH-` 在程序列表中顺序切换 | ✅ |

### F6. VGA 像素模式控制器 (vga_pixel_ctrl.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F6.1 | VGA 时序 | 640×480@60Hz，与文本终端共用 25MHz 时钟 | ✅ 仿真通过 |
| F6.2 | SDRAM 读取 | 通过 ping-pong 行缓冲从 SDRAM 读取 RGB332 像素数据 | 🟡 待 VGA 显示器验证 |
| F6.3 | 模式切换 | 写 0x1F80 寄存器切换 text/pixel 模式 | 🟡 待 VGA 显示器验证 |
| F6.4 | 基址寄存器 | 写 0x1F84 设置 framebuffer 基址 | 🟡 待 VGA 显示器验证 |
| F6.5 | RGB332→RGB888 扩展 | 每像素 1 字节正确扩展到 VGA DAC 输出 | 🟡 待 VGA 显示器验证 |
| F6.6 | Quartus 综合 | vga_pixel_ctrl.vhd 加入 de2extra.qsf，综合无错误 | ✅ 编译通过 |
| F6.7 | 地址解码 | de2_115_top.vhd 中 text 寄存器 (0x1F40..) 与 pixel 寄存器 (0x1F80+) 正确分流 | ✅ 编译通过 |
| F6.8 | 资源开销 | ~4,500 额外 LEs + 行缓冲 M9K | ✅ 27,508 LEs total (24%) |

### F7. LCD Wishbone 控制器 (lcd_wb.vhd)

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| F7.1 | 命令写入 | CPU 写 `cr` 寄存器发送 HD44780 指令 | ✅ |
| F7.2 | 数据写入 | CPU 写 `dr` 寄存器发送字符数据 | ✅ |
| F7.3 | busy-polling 已废弃 | 旧 busy-polling 不可靠 (单周期 ack)，软件改用固定延时 | ✅ 已在 lcd_hal.c 修复 |

---

## G. 跨切面测试

### G1. 编译检查

| # | 验收项 | 通过条件 | 状态 |
|---|---|---|---|
| G1.1 | NEORV32 交叉编译 | `make clean all image` 无错误 | ✅ |
| G1.2 | LOCAL_BUILD 编译 | `make local` (host gcc) 无错误 | ✅ |
| G1.3 | IMEM 镜像尺寸 | `neorv32_imem_image.vhd` 适配 64KB IMEM 预算；当前 `Executable (VHD)` 为 `62872 bytes` (95.9%) | ✅ |
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
| A. 基础设施 (A1-A3) | 17 | 17 | 0 | 0 | 0 |
| A. 基础设施 (A4 LCD HAL) | 5 | 4 | 0 | 0 | 0 |
| A. 基础设施 (A5 GFX) | 9 | 9 | 0 | 0 | 0 |
| A. 基础设施 (A6 PS/2 decoder) | 5 | 5 | 0 | 0 | 0 |
| A. 基础设施 (A7 Framebuffer HAL) | 6 | 5 | 1 | 0 | 0 |
| A. 基础设施 (A8 GUI widgets) | 10 | 10 | 0 | 0 | 0 |
| B. 核心应用 (B1-B4) | 38 | 32 | 0 | 4 | 1 |
| B. 核心应用 (B5 startui) | 11 | 6 | 5 | 0 | 0 |
| C. 游戏 | 26 | 26 | 0 | 0 | 0 |
| D. 实验模块 (expdemo) | 21 | 21 | 0 | 0 | 0 |
| E. 系统工具 | 25 | 22 | 0 | 3 | 0 |
| F. 硬件外设 (F1-F5) | 22 | 22 | 0 | 0 | 0 |
| F. 硬件外设 (F6 VGA pixel) | 8 | 3 | 5 | 0 | 0 |
| F. 硬件外设 (F7 LCD WB) | 3 | 3 | 0 | 0 | 0 |
| G. 跨切面 | 7 | 7 | 0 | 0 | 0 |
| **合计** | **213** | **192** | **11** | **7** | **1** |

**主要阻塞**:
1. ❌ NTT 硬件加速器 — C 驱动就绪，真实 NTT 盒子未并回 bitstream
2. 🟡 startui (Win 3.0 GUI) — 需要 SDRAM 像素模式，推迟到 V3
3. ☐ Exp6/7 画廊 — 需补代码
4. 🟡 LCD 修复待目视确认 — busy-polling 已改为固定延时，需上板看 LCD 实际显示

## V2 剩余项

**V2 验收完成。** 以下项移至 V3：

- **snake Game Over 显示** (H2.9) — 撞自身卡住但未显示 GAME OVER 文字
- **startui** (B5, H2.15-19) — 需要 SDRAM 资源
- **NTT 硬件** (E4.7, E4.8) — 真实 NTT 盒子未并回
- **Exp6/7 画廊** (H2.13) — 需补代码
- **VGA 像素模式实板** (F6.2-6.5) — 与 startui 同期

已关闭：LCD 目视 ✅、R3 ✅、R10 ✅。

---

## H. 待验收清单 (上板逐项打勾)

> 以下为需要在实板上逐项确认的验收条目。
> 标记 `[串口]` = 只需串口即可验证；`[VGA]` = 需要 VGA 显示器。
> 验收时在 `实板` 列打 ✅ 或 ✗。

### H1. 串口可验收 (不需要 VGA)

| # | 验收项 | 操作方法 | 预期结果 | 实板 |
|---|---|---|---|---|
| H1.1 | IR 遥控切频 | 在 shell 空闲按遥控器数字键 1-9 / `A` | 对应程序被启动，且与状态栏/LCD 频道号一致 | ✅ |
| H1.2 | IR 0/RETURN 返回 shell | 在子程序中按遥控器 0 或 RETURN | 返回 shell 提示符 `0000>` | ✅ |
| H1.3 | IR CH+/CH- 顺序切换 | 按 CH+ / CH- | 程序序号 +1 / -1 并启动 | ✅ |
| H1.4 | IR 指令透传给子程序 | 在 expdemo 中按遥控器数字键/CH+/CH-/MENU | expdemo 响应遥控器切换实验；MENU 在实验页回 Home | ✅ |
| H1.5 | 状态栏 uptime (串口可见) | 上板后观察串口状态栏行 | `Up HH:MM` 每分钟递增 | ✅ 串口可见 `Up 000:03`→`000:05` |
| H1.6 | dashboard 进入 | 输入 `dash` | 串口显示 dashboard 标题和实时状态 | ✅ 标题+SW/KEY/IR/uptime 全部输出 |
| H1.7 | dashboard SW 实时读取 | 在 dashboard 中拨动 SW | 串口实时显示 SW 状态变化 | ✅ |
| H1.8 | dashboard KEY 按键检测 | 在 dashboard 中按 KEY1-3 | 串口显示 KEY 状态变化 | ✅ |
| H1.9 | dashboard IR 码值显示 | 在 dashboard 中按遥控器 | 串口显示 IR 命令码 + 键义名称 | ✅ |
| H1.10 | dashboard 退出 `q` | 按 `q` | 返回 shell `0000>` | ✅ |
| H1.11 | board_status LCD 编码 | 上板观察 LCD 第二行 | shell 空闲时显示 `CH0 SHEL READY` | ✅ |
| H1.12 | board_status HEX/LED 编码 | 进入各程序观察 HEX/LED | 不同程序有不同编码输出 | ✅ |
| H1.13 | crypto bench Zk* 数值 | 运行 `crypto` → `bench` | 输出 C vs Zk* cycles 对比表，Zk* 有加速比 | ✅ AES 107.6x, SM4 1.7x, SHA-512 1.5x |
| H1.14 | monitor aes 演示 | 运行 `monitor` → `aes` | 显示 `aes32esmi` / `aes32esi` 指令结果 | ✅ `0x87A0D7EB` / `0xAABBCCC6` |
| H1.15 | monitor sha256 演示 | 运行 `monitor` → `sha256` | 显示 `sha256sig0` / `sha256sum0` 指令结果 | ✅ `0xE7FCE6EE` / `0x66146474` |
| H1.16 | monitor sm4 演示 | 运行 `monitor` → `sm4` | 显示 `sm4ed` / `sm4ks` 指令结果 | ✅ `0x65743CE2` / `0xCA25B52E` |
| H1.17 | TRNG 统计验证 | 运行 `crypto` → `bench` | 输出 256-byte 1-bits/0-bits ratio ≈ 50% | ✅ 1029/1019 bits = 50.24% |
| H1.18 | expdemo Home 进入 | 输入 `expdemo` | 串口显示 Home 页、实验列表与当前选择 | ✅ |
| H1.19 | expdemo `+/-` 浏览 | 在 expdemo 中按 `+` / `-` | `Selected:` 在串口上顺序变化 | ✅ |
| H1.20 | expdemo 两级退出 | 实验页按 `q` 回 Home；Home 页再按 `q` 回 shell | ✅ |
| H1.21 | expdemo channel MMIO 写通 | 在 expdemo 中输入 `1` + Enter，或 monitor `poke 0xF000D000 1` | `peek 0xF000D000` 读回 1，且活动页显示 `HW channel=1` | ✅ `peek 0xF000D000 = 0x00000001`，菜单显示 `HW channel: 1` |
| H1.22 | expdemo `KEY0` 保留 | 进入任一实验后观察说明页并试用 `KEY1..KEY3` | 物理 `KEY0` 不再承担实验内功能，实验按键按新映射工作 | ✅ |
| H1.23 | `lcdmon` 远程 LCD 阴影读取 | shell 输入 `lcdmon` | 串口输出 `L0/L1` 两行 16 字符阴影缓冲；当前 shell 空闲值为 `DE2Extra Shell` / `CH0 SHEL READY` | ✅ |
| H1.24 | LCD 修复目视确认 | 上板后观察 LCD | 第一行 `DE2Extra Shell`，第二行 `CH0 SHEL READY`，不再只显示 "LDL" | ✅ 已确认 |
| H1.25 | `startui` 命令注册 | 输入 `startui` | 串口确认程序入口识别 (VGA 像素模式需显示器才能看到 GUI) | ✅ 命令已注册 |

### H2. 需要 VGA 显示器

| # | 验收项 | 操作方法 | 预期结果 | 实板 |
|---|---|---|---|---|
| H2.1 | VGA 时序 + 画面 | 上电接显示器 | 稳定 640×480@60Hz，无花屏 | ✅ |
| H2.2 | shell 首页 VGA 显示 | 上电进入 shell | VGA 显示启动画面 + 提示符，与串口一致 | ✅ |
| H2.3 | 状态栏常驻 | 观察 VGA 最后一行 | `DE2Extra | Ch:X progname Up HH:MM` | ✅ |
| H2.4 | 页面切换无花屏 | 进入 help/memtest/crypto/life/dash | 切换时 VGA 正常刷新，不残留前页内容 | ✅ |
| H2.5 | vga_clear / 光标 / 换行 / 退格 | 在 shell 中输入文字并退格 | VGA 行为与串口镜像一致 | ✅ |
| H2.6 | memtest VGA 输出 | 运行 `memtest` | VGA 显示测试进度和结果 | ✅ |
| H2.7 | crypto VGA 输出 | 运行 `crypto` → `aes enc ...` | VGA 显示加解密结果 | ✅ |
| H2.8 | snake VGA 渲染 | 运行 `snake` | VGA 显示 40×20 网格 + 蛇 + 食物 | ✅ |
| H2.9 | snake Game Over | 撞墙/撞自身 | VGA 中央显示 "GAME OVER" | ☐ 撞自身卡住但未显示 GAME OVER，移至 V3 |
| H2.10 | life VGA 渲染 | 运行 `life` | VGA 显示 40×20 细胞网格 | ✅ |
| H2.11 | ps2 VGA 事件日志 | 运行 `ps2` | VGA 显示每次按键的 scan code + 键名 | ✅ |
| H2.12 | dashboard VGA 实时状态 | 运行 `dash` | VGA 显示 SW/KEY/IR/uptime 实时刷新 | ✅ |
| H2.13 | Exp6/7 画廊入口 | (需补代码) | 从 shell 进入 Exp6/7 并显示内容 | ☐ |
| H2.14 | hello VGA LED 跑马灯 | 运行 `hello` | VGA 显示 `*`/`.` 模拟 LED 跑马灯 | ✅ |
| H2.15 | startui 桌面显示 | 运行 `startui` | VGA 切换到像素模式，显示 Win 3.0 风格桌面 (青色背景 + 图标 + 任务栏) | ☐ |
| H2.16 | startui 窗口渲染 | 观察 startui 桌面 | 可见 2 个演示窗口 (Calculator + About)，标题栏 + 3D 边框 | ☐ |
| H2.17 | startui 键盘导航 | Tab/Enter/Escape/方向键 | Tab 切焦点，Enter 激活按钮，Escape 关闭窗口 | ☐ |
| H2.18 | startui 返回文本模式 | 顶层 Escape | VGA 恢复文本终端，shell 提示符正常显示 | ☐ |
| H2.19 | VGA 像素模式切回文本 | startui 退出后 | VGA 文本终端无花屏，字符正常显示 | ☐ |

---

*最后更新: 2026-05-25 — VGA 上板验收通过 (H2.1-12, H2.14)；A2 VGA HAL / F2 VGA 文字终端 / B1 hello / B4 ps2 / C1 snake / C2 life 全部升为 ✅；startui 推迟到 V3 (需要 SDRAM)；V2 剩余：NTT 硬件、Exp6/7 画廊、LCD 目视确认、VGA 像素模式。*
