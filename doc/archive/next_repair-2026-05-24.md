# DE2Extra 下一轮修复指引（归档）

> 归档日期: 2026-05-24  
> 归档原因: `next_repair.md` 原文同时混合了“已修完记录”和“剩余待办”。  
> 2026-05-24 之后，VGA 相关剩余项已拆分到 `doc/vga_check.md`，其余内容作为阶段归档保留。

---

## 已收口事项

- SDRAM 控制器读回采样与地址切分已稳定
- `de2shell/memtest` 五项测试已实板 `PASS`
- `crypto bench` 已实板跑通
- SW / KEY / UART / IR 主路径已打通
- Exp10 遥控器码表已按物理键名收口
- `build.sh` 不再被视为唯一稳定入口，手动构建 / 烧录路径已文档化

---

## 归档时仍未收口的方向

这些项并非全部完成，而是已经不再适合继续塞在 `next_repair.md` 里混写：

1. VGA 实显链路
2. Exp6 / Exp7 画廊频道
3. `dashboard / board_status` 的最后一次实板确认
4. `crypto bench` 输出口径的最终验收
5. 构建链与文档持续整理

其中 VGA 相关内容已单独迁移到：

- `doc/vga_check.md`

---

## IR 修复历史（诊断上下文保留）

旧文档 4.5 节详细记录了 IR 接入后导致 UART 假死的诊断与修复过程，摘要如下：

### 根因链

1. `main.c` 首版用 `timer_wb` 做软件 NEC 解码，`timer_wb` 轮询阻塞等待第一下红外边沿，直接卡死 UART 输入
2. 后改走 `handle_ir_events()` 处理 IR 事件，但该函数同样阻塞等待 IR 事件，导致主循环永远跑不到 `uart_kbhit()`
3. 计时窗口按 NEC 下降沿间隔写，但 `timer_wb` 捕获的是上升沿，软件层等于造了一套未经板测的新解码器

### 修复路径

- 回到 `ir_nec_wb` 硬件解码寄存器链路（已有 VHDL NEC 解码器）
- `timer_wb` 轮询从主循环热路径中移除
- `handle_ir_events()` 改为非阻塞查询（检查 `ir_nec_wb` 的 valid 标志位）

### 验收结果

- IR 端到端已通过：遥控器数字键 `1-7`、`0/RETURN`、`CH+/CH-` 切换正常
- 子程序 `ir_input` 回调优先级高于全局 IR 映射
- dashboard 显示最近一次 IR 命令码与键义

如果将来 IR 再出问题，对照这条链排查：`ir_nec_wb` 寄存器是否正常 → 主循环是否被阻塞 → `handle_ir_events` 是否非阻塞。

---

## 归档备注

如果后续需要回看 2026-05-24 这一轮修复背景，优先结合以下文档一起看：

- `doc/编译烧录前必看.md`
- `doc/de2shell-module-acceptance.md`
- `doc/vga_check.md`
