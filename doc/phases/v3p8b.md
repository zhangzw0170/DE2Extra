# V3P8b: LCD 显示内容重设计

日期: 2026-06-03
状态: **代码完成, 待板载验收**

## 背景

`board_status.c` 中 `program_title()` / `program_abbr()` 的 ID 映射已严重过期:
- ID 5 起全部错位 (旧编号 5=Life 已删除, 实际 5=INFO)
- `lcd_status.vhd` RTL 侧 `prog_abbr_char` 同样过期 (但当前未被例化)

## 新格式

### Line 1 (统一格式, 16 字符)

```
DE2Ex XX AAAAAA
```

- `DE2Ex` (5ch) + 空格 (1ch) + 2位十进制ID (2ch) + 空格 (1ch) + 6ch缩写补空格 (6ch) + 尾空格 (1ch) = 16ch

### Line 2 (每程序特化, 16 字符)

| ID | PROG        | abbr (6ch) | Line 1 示例        | Line 2 内容                          | Line 2 示例            | data (16-bit) 编码                          |
|----|-------------|-----------|--------------------|---------------------------------------|------------------------|---------------------------------------------|
| 0  | SHELL       | `SHELL `  | `DE2Ex 00 SHELL ` | 状态文本 (heap/uptime 已在 HEX)       | `READY            `   | 无 (t_status 驱动)                          |
| 1  | HELLO       | `HELLO `  | `DE2Ex 01 HELLO ` | 运行标记 (counter 已在 HEX)           | `RUNNING           `  | 无                                          |
| 2  | CRYPTO      | `CRYPTO`  | `DE2Ex 02 CRYPTO` | 进度条 (CPU 阻塞时 LCD 是唯一可见输出) | `AES [======]  75%`  | subtest_id(8) + progress%(8)                |
| 3  | KBD         | `KBD   `  | `DE2Ex 03 KBD   ` | 最近按键 + Lock 指示灯                | `Shift+A       N--`  | ascii(8) + shift/ctrl/alt(3) + N/C/S(3) +2  |
| 4  | SNAKE       | `SNAKE `  | `DE2Ex 04 SNAKE ` | 当前速度等级                          | `SPEED: 5         `  | speed_level(16)                             |
| 5  | INFO        | `INFO  `  | `DE2Ex 05 INFO  ` | 软件构建时间                          | `SW 20260603 1335`  | 无 (固定, 从 SW_BUILD_TAG 编译时注入)        |
| 6  | RISCV       | `RISCV `  | `DE2Ex 06 RISCV ` | 当前 PC 值低 24 位                    | `PC:003A5F        `  | pc_lo(16)                                   |
| 7  | EXP         | `EXP   `  | `DE2Ex 07 EXP   ` | 实验编号 + 名称                       | `E5  COUNTER      `  | exp_id(8) + 0(8)                            |
| 8  | TWM         | `TWM   `  | `DE2Ex 08 TWM   ` | CPU + GPU 占用                        | `CPU:45% GPU:30% `  | cpu_pct(8) + gpu_pct(8)                     |
| 9  | CONWAY      | `CONWAY`  | `DE2Ex 09 CONWAY` | 代数 + 人口                           | `G:1234   P:56   `  | gen_lo(16) 或 gen(8)+pop_lo(8)              |
| 10 | NTT         | `NTT   `  | `DE2Ex 10 NTT   ` | 进度条 (同 CRYPTO, CPU 阻塞时可见)    | `NTT [======]  75%`  | subtest_id(8) + progress%(8)                |
| 11 | SYNTH       | `SYNTH `  | `DE2Ex 11 SYNTH ` | 双声道音符                            | `L:A4    R:C5    `  | note_l(8) + note_r(8) (MIDI note#)          |
| 12 | PFORTH      | `PFORTH`  | `DE2Ex 12 PFORTH` | 栈深度 + OK/>                         | `DEPTH:3     OK   `  | stack_depth(16)                             |

## Line 2 详细设计

### CRYPTO 进度条
CPU 在 bench 期间阻塞, VGA 无法更新, LCD 是唯一可见进度指示。

```
AES [======]  75%
```

- 算法名 (3ch) + 空格 (1ch) + `[` (1ch) + 进度条 (6ch) + `]` (1ch) + 空格 (1ch) + 百分比 (3ch)
- 子测试: AES-ENC, AES-DEC, SHA256, SM4 等
- 每个 subtest 完成时更新一次 LCD (bench 函数间插入 lcd 调用)

### KBD 键盘指示灯
- 位置 0-11: 最近按下的键名 (包括组合键: Shift+A, Ctrl+C, Alt+X)
- 位置 13: NumLock → `N`(开) / `-`(关)
- 位置 14: CapsLock → `C`(开) / `-`(关)
- 位置 15: ScrollLock → `S`(开) / `-`(关)

HD44780 反色需要 CGRAM 自定义字符 (占 3/8 槽位)。备选: 直接用大写 N/C/S vs `-`, 视觉区分已足够。

### NTT 进度条
同 CRYPTO 格式, NTT 运算 (NTT/INTT/点乘) 期间 CPU 阻塞。

```
NTT [======]  75%
```

### EXP 实验编号
```
E5  COUNTER
```
- `E` + 实验号 (1-13) + 空格 + 实验缩写名

### SYNTH 双声道
```
L:A4    R:C5
```
- 左声道音符 + 右声道音符
- 音符格式: 音名 (A-G) + 升降号 (#/b 或空格) + 八度 (0-9)
- 静音时显示 `--`

### TWM CPU/GPU 占用
```
CPU:45% GPU:30%
```
- 由 TWM 任务定期更新 data 字段

## 修改清单

1. **sw/lib/board_status.c**
   - `program_title()` → 统一格式 `"DE2Ex XX AAAAAA"`
   - `program_abbr()` → 更新所有 13 个程序缩写
   - `lcd_render_program()` → Line 2 改为 per-program 特化渲染
   - 新增 `lcd_render_program_data()` 或扩展 data 参数解码

2. **sw/lib/board_status.h**
   - 确认 PROG_ID 与 main.c 一致

3. **各程序 (sw/lib/*.c)**
   - 在适当位置调用 `board_status_set_program()` 传入有意义的 data
   - crypto.c: bench 循环中插入进度更新
   - synth.c: 传入左右声道 MIDI note
   - twm.c: 传入 CPU/GPU 占用
   - ps2.c: 传入按键 + lock 状态
   - conway_hw.c: 传入 generation/population

4. **src/rtl/periph/lcd_status.vhd** (可选, 当前未例化)
   - `prog_abbr_char` 函数同步更新, 保持一致

## 已完成的修改

- [x] **sw/lib/board_status.c** — 完全重写: `build_line1()` 统一格式, `render_line2()` 13 个程序特化, `render_progress_bar()` 共用进度条
- [x] **prog_id 修正** — info.c 6→5, monitor.c 7→6, demo.c 8→7, twm.c 9→8, conway_hw.c 10→9, synth.c 13→11, ntt.c #define 12→10
- [x] **crypto.c** — 5 阶段 bench 进度条 (每 128 iter 更新 LCD)
- [x] **ntt.c** — roundtrip 0%/50%/75%/100% 进度
- [x] **synth.c** — `update_lcd_note()` 按键开/关时更新 L/R MIDI note
- [x] **conway_hw.c** — data 改为 gen_lo(8)+pop_lo(8)
- [x] **编译通过** — 200KB, 无 error/warning

## 待后续补充

- [ ] snake.c 传入速度等级
- [ ] demo.c 传入 exp_id
- [ ] monitor.c 传入 PC 值
- [ ] ps2.c 传入按键 + N/C/S lock 状态
- [ ] twm.c 传入 CPU/GPU%

## 不修改

- lcd_wb.vhd (Wishbone 接口不变)
- lcd_hal.c / lcd_hal.h (底层驱动不变)
- Line 1 格式硬编码在 board_status.c, 不走 RTL

---

## 验收表 (待板载验证)

### A. 基础功能

| # | 验收项 | 操作 | 预期结果 | 通过 |
|---|--------|------|----------|------|
| A1 | LCD 初始化 | 上电/烧录后等待 ~2s | LCD 亮, 显示内容可见 | □ |
| A2 | Shell Line1 | 进入 shell 空闲 | `DE2Ex 00 SHELL ` | □ |
| A3 | Shell Line2 | 进入 shell 空闲 | `READY            ` | □ |
| A4 | HEX 不受影响 | shell 空闲 | HEX5-4 显示 heap%, HEX3-0 显示 uptime | □ |
| A5 | LCD cache 生效 | shell 空闲不动 | LCD 无闪烁 (不重复写入) | □ |

### B. 各程序 Line 1 验证

| # | 程序 | 命令 | 预期 Line 1 | 通过 |
|---|------|------|-------------|------|
| B1 | HELLO | `hello` | `DE2Ex 01 HELLO ` | □ |
| B2 | CRYPTO | `crypto` | `DE2Ex 02 CRYPTO` | □ |
| B3 | KBD | `kbd` | `DE2Ex 03 KBD   ` | □ |
| B4 | SNAKE | `snake` | `DE2Ex 04 SNAKE ` | □ |
| B5 | INFO | `info` | `DE2Ex 05 INFO  ` | □ |
| B6 | RISCV | `riscvasm` | `DE2Ex 06 RISCV ` | □ |
| B7 | EXP | `expdemo` | `DE2Ex 07 EXP   ` | □ |
| B8 | TWM | `twm` | `DE2Ex 08 TWM   ` | □ |
| B9 | CONWAY | `conway` | `DE2Ex 09 CONWAY` | □ |
| B10 | NTT | `ntt` | `DE2Ex 10 NTT   ` | □ |
| B11 | SYNTH | `synth` | `DE2Ex 11 SYNTH ` | □ |
| B12 | PFORTH | `pforth` | `DE2Ex 12 PFORTH` | □ |

### C. 各程序 Line 2 特化验证

| # | 程序 | 操作 | 预期 Line 2 | 通过 |
|---|------|------|-------------|------|
| C1 | HELLO | 进入后观察 | `RUNNING           ` | □ |
| C2 | CRYPTO bench | `crypto` → `bench` | 进度条从 `AES [      ]   0%` 渐进到 `SM4 [======] 100%` | □ |
| C3 | CRYPTO 空闲 | `crypto` 不跑 bench | 显示固定状态 (非进度条) | □ |
| C4 | KBD | 按 A 键 | 左侧显示 `'A'`, 右侧 3 位 lock 指示灯 | □ |
| C5 | KBD lock | 按 NumLock 键 | 位置 13 从 `-` 变 `N` | □ |
| C6 | KBD lock | 按 CapsLock 键 | 位置 14 从 `-` 变 `C` | □ |
| C7 | SNAKE | 进入观察 | `SPEED: X` 显示当前速度 | □ |
| C8 | INFO | 进入观察 | `SW ` + 日期时间信息 | □ |
| C9 | RISCV | 进入观察 | `PC:` + 4 位 hex | □ |
| C10 | EXP | 选择实验 5 | `E5` + 实验名 | □ |
| C11 | TWM | 进入观察 | `CPU:X% G:X%` 格式 | □ |
| C12 | CONWAY | 运行后观察 | `G:XXX` + `P:XX` (代数+人口变化) | □ |
| C13 | CONWAY 编辑/运行 | 切换模式 | Line 2 gen/pop 随运行更新 | □ |
| C14 | NTT roundtrip | `ntt` → `roundtrip` | 进度条 `NTT [======]  75%` | □ |
| C15 | SYNTH 按键 | 按 A 键 (Track 1) | L 通道显示音符, 如 `L:C4` | □ |
| C16 | SYNTH 双声道 | 同时按 Track1+Track2 | `L:XX` 和 `R:XX` 同时更新 | □ |
| C17 | SYNTH 释放 | 松开所有键 | `L:--` `R:--` (或保持最后音符) | □ |
| C18 | PFORTH | 进入观察 | `DEPTH:X     OK` | □ |

### D. 退出恢复

| # | 验收项 | 操作 | 预期结果 | 通过 |
|---|--------|------|----------|------|
| D1 | 程序退出→Shell | 任意程序 F10 退出 | Line1 恢复 `DE2Ex 00 SHELL ` | □ |
| D2 | 程序退出→HEX | 任意程序 F10 退出 | HEX 恢复 heap%+uptime | □ |
| D3 | expdemo LCD 切换 | expdemo 进入→退出 | expdemo 退出后 LCD 恢复 shell 控制 (1ms reset 生效) | □ |

### E. 边界情况

| # | 验收项 | 操作 | 预期结果 | 通过 |
|---|--------|------|----------|------|
| E1 | 快速切换程序 | 连续 hello→F10→snake→F10 | LCD 每次正确切换, 无残留 | □ |
| E2 | 进度条 0% | crypto bench 开始瞬间 | `AES [      ]   0%` | □ |
| E3 | 进度条 100% | crypto bench 结束 | 最后一个阶段达到 100% | □ |
| E4 | 长时间运行 | shell 空闲 >5min | LCD 稳定, cache 正常, 无乱码 | □ |
