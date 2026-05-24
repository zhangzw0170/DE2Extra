# DE2Extra VGA 检查单

> 更新日期: 2026-05-24  
> 适用范围: `de2shell` 的 VGA 实显闭环、状态栏、页面切换以及 Exp6 / Exp7 画廊补齐

---

## 1. 当前结论

除 VGA 相关内容外，`de2shell` 当前主路径已经基本收口:

- shell / `memtest` / `crypto` / `life` / `dashboard` 均可进入
- SW / KEY / IR / UART 都已实板修复
- IR 码表已按 Exp10 物理键名收口，不再存在 `0x1A` / `CH+` 歧义
- 手动 `Docker -> 拷 IMEM -> Quartus compile -> quartus_pgm` 构建烧录链路稳定

当前真正剩下的主阻塞项，已经主要集中在 VGA 实显与基于 VGA 的展示页。

---

## 2. 待确认项

### 2.1 VGA 实屏显示

需要确认以下内容在真实显示器上都正常：

1. 上电进入 shell 后，VGA 实屏与串口输出一致
2. 状态栏常驻，频道名和 uptime 显示正常
3. `help / memtest / crypto / life / dash` 页面切换无花屏
4. `vga_clear()`、光标、换行、退格行为与串口镜像一致
5. `dashboard` 页面在实屏上能稳定刷新 SW / KEY / IR / uptime

### 2.2 Exp6 / Exp7 画廊频道

VGA 路径一旦确认稳定，就要补齐至少一个正式展示入口：

1. Exp6 或 Exp7 至少有一个能稳定显示
2. 能从 shell 正式进入，而不是临时测试代码
3. 页面风格与当前 `de2shell` 状态栏 / 退出逻辑一致

---

## 3. 相关代码

- `src/rtl/periph/vga_text_terminal.vhd`
- `sw/app/de2shell/vga_hal.c`
- `sw/app/de2shell/vga_hal.h`
- `sw/app/de2shell/main.c`
- `sw/app/de2shell/dashboard.c`
- `src/rtl/de2_115_top.vhd`
- `par/de2extra.qsf`

---

## 4. 相关资料

- `doc/phases/phase2b-vga-terminal.md`
- `doc/phases/phase3-integration.md`
- `doc/de2shell-module-acceptance.md`
- `DE2-115_v.3.0.6_SystemCD/`
- `E:\Main\JuniorII\NonExam\FPGA\DE2-115引脚表.xlsx`

---

## 5. 建议验证顺序

1. 先只验证 shell 首页和状态栏
2. 再验证 `dashboard`
3. 再验证 `memtest / crypto / life` 的页面切换
4. 最后补 Exp6 / Exp7 的正式入口

---

## 6. 验收口径

- VGA 实屏内容与串口镜像基本一致
- 页面切换稳定，不花屏、不丢状态栏
- `dashboard` 在 VGA 上能稳定显示实时状态
- Exp6 / Exp7 至少有一个正式入口完成并可实机展示
