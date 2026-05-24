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

## 归档备注

如果后续需要回看 2026-05-24 这一轮修复背景，优先结合以下文档一起看：

- `doc/编译烧录前必看.md`
- `doc/de2shell-module-acceptance.md`
- `doc/vga_check.md`
