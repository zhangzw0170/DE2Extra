# ChromaShader — 程序化地形探索游戏

> 状态: Draft | 日期: 2026-05-25 | 依赖: V2 文字终端
> 硬件: 纯 FPGA 噪声网络 + BRAM 帧缓冲 | 软件: PS/2 键盘 + UART

## 概述

WASD 滚动无限程序化世界，采集金矿。地形由硬件噪声网络实时生成——2000 个字符格在 40μs 内填满，零 CPU 开销。

跑在 V2 80×25 文字终端上，每格 8×16 像素，前景色铺满。

---

## 1. 哈希函数

一个 50MHz 周期内产出 32-bit 伪随机值。纯 XOR + 移位，不用乘法器。

```
h ← seed XOR (wx << 7) XOR (wy << 20)
h ← h XOR (h << 13)
h ← h XOR (h >> 17)
h ← h XOR (h << 5)
h ← h XOR (wy << 3) XOR (wx << 16)
h ← h XOR (h >> 11)
h ← h XOR (h << 7)
return h
```

参数: `wx = world_x`, `wy = world_y`, `seed = global_seed[31:0]`

---

## 2. 地形映射

取 `h[7:0]` 为高度 (0-255)：

| 高度 | 地形 | 类型码 | RGB332 | 说明 |
|------|------|--------|--------|------|
| 0-55 | 深水 | 000 | `0b000_00_011` | |
| 56-75 | 浅水 | 001 | `0b000_10_100` | |
| 76-95 | 沙滩 | 010 | `0b11_10_101` | |
| 96-165 | 草地 | 011 | `0b001_11_001` | |
| 166-195 | 森林 | 100 | `0b000_10_010` | |
| 196-225 | 山岩 | 101 | `0b10_10_010` | |
| 226-255 | 雪峰 | 110 | `0b11_11_111` | |

**颜色变化**: 取 `h[15:8]` 低 2 位，在 RGB332 某个通道上 ±1，打散纯色块。

**金矿**: `h[23:16] = 0x5A` 时标记 `has_gold=1` (概率 ≈ 0.4%，每屏约 8 个)。渲染时前景色 `0b11_11_00` (亮黄) + 字符 `●`，叠在地形背景上。

---

## 3. 硬件架构

```
                    ┌──────────────────┐
   offset_x ────────┤                  │
   offset_y ────────┤   chroma_noise   │── terrain_type[2:0]
   global_seed ─────┤   (纯组合逻辑)    │── fg_color[7:0]
   cell_x ──────────┤                  │── bg_color[7:0]
   cell_y ──────────┤                  │── has_gold
                    └──────────────────┘
                           │
                    ┌──────▼──────┐      ┌─────────────┐
   fill_fsm ────────┤ chroma_fb   │      │ chroma_mod  │
   (addr 0→1999)    │ 2048×16bit  │      │ 2048×18bit  │
   1 cell/cycle     │ dual-port   │      │ dual-port   │
   40μs/frame       │ BRAM ×4 M9K │      │ BRAM ×4 M9K │
                    └──────┬──────┘      └──────┬──────┘
                           │                    │
                    ┌──────▼────────────────────▼──────┐
   player_x ────────┤                                  │
   player_y ────────┤        chroma_output             │──→ VGA MUX
                    │  (MUX + player overlay)          │
                    └──────────────────────────────────┘
```

**填充时序**:
- offset 或 seed 变化 → `fill_fsm` 启动
- 逐格: `cell_x = addr % 80`, `cell_y = addr / 80`
- `world_x = cell_x + offset_x`, `world_y = cell_y + offset_y`
- 2000 周期 (40μs @ 50MHz) 填满全帧
- 填充期间 **锁定** offset/seed 寄存器，防止画面撕裂

**双端口 BRAM**:
- Port A (50MHz): 噪声写入 / CPU 读写修改层
- Port B (25MHz): VGA 持续读取

---

## 4. 修改层

每格 18 位:

| 位 | 含义 |
|----|------|
| [17] | valid (1=覆盖噪声值) |
| [16] | has_gold |
| [15:8] | fg_color |
| [7:0] | bg_color |
| [2:0] | terrain_type |

- **涂色 (paint)**: CPU 写 `{valid=1, ...}` → 该格永久覆盖噪声
- **擦除 (erase)**: CPU 写 `{valid=0}` → 恢复噪声生成值
- CTRL[2] 写 1 → 批量清空所有修改 (clear_all_mods)

---

## 5. 寄存器映射

基地址 `0xF000E000` — NOTE: This address is now occupied by SD card SPI. ChromaShader needs a new address assignment when implemented.

| 偏移 | R/W | 名称 | 位段 |
|------|-----|------|------|
| `0x00` | R/W | CTRL | [0]=enable, [1]=force_refresh, [2]=clear_all_mods |
| `0x04` | R/W | SEED | [31:0] global_seed |
| `0x08` | R/W | OFF_X | [15:0] 世界偏移 X (有符号, 单位=格) |
| `0x0C` | R/W | OFF_Y | [15:0] 世界偏移 Y |
| `0x10` | R/W | PLAYER_X | [6:0] 玩家 X (0-79) |
| `0x14` | R/W | PLAYER_Y | [4:0] 玩家 Y (0-24) |
| `0x18` | R | CELL | [2:0]=地形类型, [3]=has_gold, [15:8]=前景色, [23:16]=背景色 |
| `0x1C` | W | PAINT | [2:0]=地形类型, [7]=has_gold, [15:8]=前景色, [23:16]=背景色, [24]=触发 |
| `0x20` | R | STATUS | [0]=busy, [1]=frame_ready |

CELL 返回 PLAYER_X/Y 所指格子的当前数据（优先修改层）。
PAINT 向 PLAYER_X/Y 所指格子的修改层写入；`[24]=1` 触发写操作。

---

## 6. 玩家渲染

`chroma_output` 逐格输出时检查坐标:

| 条件 | ASCII | FG | BG |
|------|-------|----|----|
| 该格有金矿 | `●` (0x0F) | 亮黄 | 地形背景 |
| 该格 = 玩家位置 | `@` (0x40) | 亮白 | 地形背景 |
| 其他 | `█` (0xDB) | 地形前景 | 地形背景 |

---

## 7. VGA 集成

在 `vga_text_terminal.vhd` 渲染管线插入 MUX:

```vhdl
if chroma_enable = '1' then
    ascii  <= chroma_ascii;
    fg_rgb <= rgb332_to_rgb565(chroma_fg);
    bg_rgb <= rgb332_to_rgb565(chroma_bg);
else
    ascii  <= char_ram_ascii;
    fg_rgb <= char_ram_fg;
    bg_rgb <= char_ram_bg;
end if;
```

RGB332 → RGB565 扩展:
```
R565[4:0] = {R332[2:0], R332[2:1]}
G565[5:0] = {G332[2:0], G332[2:0]}
B565[4:0] = {B332[1:0], B332[1:0], B332[1]}
```

---

## 8. 游戏循环 (C 软件)

```
INIT:
    chroma_set_seed(random)
    gold = 0, px = 40, py = 12

LOOP:
    c = ps2_getchar()

    if c in {W,A,S,D}:
        update px, py, off_x, off_y
        chroma_set_player(px, py)
        chroma_set_offset(off_x, off_y)
        chroma_wait_frame()          // 等 STATUS.frame_ready

    if c == 'E':
        cell = chroma_read_cell()     // 读 CELL 寄存器
        if cell.has_gold:
            gold++
            chroma_paint(GRASS, 0, GRASS_FG, GRASS_BG)  // 采后恢复草地
            uart_printf("Gold: %d/10\n", gold)
        else:
            uart_puts("nothing here\n")

    if gold >= 10:
        uart_puts("YOU WIN\n")
        break
```

---

## 9. 操作

| 键 | 动作 |
|----|------|
| W/A/S/D | 移动玩家 + 滚动世界 |
| E | 采集当前格资源 |
| 1 | 涂草地 |
| 2 | 涂水 |
| 3 | 涂围墙 (灰) |
| 0 | 清除所有涂改 |
| Q | 退出 |

---

## 10. 资源预算

| 模块 | LE | M9K | 备注 |
|------|-----|-----|------|
| 哈希函数 (纯组合) | ~120 | 0 | 6 级 XOR-shift |
| 填充状态机 | ~40 | 0 | 11-bit 地址计数器 |
| 帧缓冲 BRAM | 0 | 4 | 2048×16 dual-port |
| 修改层 BRAM | 0 | 4 | 2048×18 dual-port |
| 寄存器 + WB 接口 | ~60 | 0 | |
| 输出 MUX + 玩家叠加 | ~40 | 0 | |
| **合计** | **~260** | **8** | |

当前 fit 基线: 11,773 LE + 680 Kb BRAM → 加 260 LE + 74 Kb 后: 12,033 LE (10.5%) + 754 Kb (19%)。

---

## 11. 与旧版设计的差异

| 项目 | 旧设计 | 本规格 |
|------|--------|--------|
| 哈希 | "1 LFSR + 坐标散列" | 6 级 XOR-shift, 确定公式 |
| 修改擦除 | 未定义 | valid bit = 0 恢复噪声 |
| 批量清除 | 无 | CTRL[2] clear_all_mods |
| 撕裂防护 | 未提 | 填充期间锁定 offset/seed |
| 资源检测 | CPU 比对颜色字面值 | CELL 寄存器返回 terrain_type[2:0] |
| 玩家渲染 | 未定义 | 硬件叠加 @ 字符 |
| 胜利条件 | 未指定 | CPU 维护 gold 计数 |

---

## 12. 验证清单

| # | 项 | 方法 |
|---|-----|------|
| 1 | 哈希分布均匀性 | 生成 256×256 高度图, Python 检查无明显条纹 |
| 2 | 填充正确性 | 固定 seed+offset, CPU 读 CELL 寄存器比对预期 |
| 3 | 修改层读写 | paint → CELL 读回 → 验证; erase → 验证恢复噪声 |
| 4 | 玩家叠加 | 移动 PLAYER_X/Y, 确认 VGA 上 @ 位置随之改变 |
| 5 | 填充锁定 | 填充期间写 OFF_X, 确认 STATUS.busy=1 且值未被锁存 |
| 6 | 端到端游戏 | WASD + E 采集金矿, UART 输出 Gold count |
