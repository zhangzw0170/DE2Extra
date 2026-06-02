# V3 Phase 3b: AES/SHA 密码学可视化

> 日期: 2026-05-25 | 状态: Planning
> 前置: V3P3A (像素帧缓冲模式 + SDL2 仿真) 可用
> 参考: `doc/phases/phase5-sdram-gui.md` 第 6 节

---

## 1. 概述

### 1.1 目标

在 VGA 像素帧缓冲上以图形化方式展示 AES-128 和 SHA-256 的内部运算流程。作为 V3 的"最终演示"功能，在答辩中直观呈现 RISC-V 密码学扩展指令 (Zkne/Zknd/Zknh) 的工作过程。

### 1.2 为什么重要

- **教学价值**: AES-128 的 10 轮 SubBytes/ShiftRows/MixColumns/AddRoundKey 和 SHA-256 的 64 轮压缩函数是密码学课程核心内容，可视化后一目了然
- **硬件演示**: NEORV32 已启用 Zkne/Zknd/Zknh 扩展，可视化直接展示这些硬件指令在流水线中的位置
- **答辩亮点**: 图形化 + 实时数据比纯文字输出更有冲击力

### 1.3 范围

| 功能 | 包含 | 不包含 |
|------|------|--------|
| AES-128 ECB | 10 轮加密/解密逐步可视化 | AES-256、CBC/CTR 模式 |
| SHA-256 | 压缩函数可视化 (64 轮) | SHA-512、SM4、SM3 |
| 交互 | 手动/自动步进、暂停、重置 | 键盘实时输入明文 |
| 显示 | 128-bit/256-bit 状态、轮计数、指令名 | 汇编级反汇编 |

---

## 2. 设计

### 2.1 AES-128 布局 (加密方向)

```
+================================================================+
|  AES-128 ECB Encryption           [Q] Quit  [R] Reset          |
+================================================================+
|                                                                 |
|  Key:   2B7E1516  28AED2A6  ABF71588  09CF4F3C                |
|  Input: 6BC1BEE2  2E409F96  E93D7E11  7393172A                |
|  Output:__________________________  (completed after round 10)|
|                                                                 |
|  +----+   +---------+   +---------+   +---------+   +------+  |
|  | A0 |-->|SubBytes |-->|ShiftRows|-->|MixColumn|-->|AddRK |  |
|  | R0 |   | sbox[]  |   | row cyc |   | GF(2^8) |   | xor  |  |
|  +----+   +---------+   +---------+   +---------+   +------+  |
|                                                            ^  |
|  Round 3 / 10                                              |  |
|  Stage: MixColumns     Cycles: 1,240                     |  |
|  Instruction: aes32esmi s0,s0,0 + xor rk[12]             |  |
|                                                             |  |
|  +-------- State Matrix (4x4 bytes) --------+              |  |
|  | A3  2F  6B  4C                           |              |  |
|  | 87  E1  D4  9A                           |              |  |
|  | 1B  C5  AA  F3                           |              |  |
|  | 42  88  37  ED                           |              |  |
|  +-----------------------------------------+              |  |
|                                                             |  |
|  +------ Round Key (4x4) --------+                          |  |
|  | 3B  47  6D  1C                |              +----------+  |
|  | DA  3B  90  48                |              |             |
|  | ... (highlighted)             |              |             |
|  +-------------------------------+              |             |
|                                                             |  |
|  [Space] Step  [A] Auto  [P] Pause  [<-][->] Goto Round    |
+================================================================+
```

**核心区域说明**:
- **顶部信息栏** (y=0..24): 标题 + Key/Input/Output 十六进制显示
- **流水线框图** (y=32..160): 4 个阶段框 (SubBytes/ShiftRows/MixColumns/AddRoundKey)，当前活跃阶段高亮绿色，已完成橙色，未执行灰色，箭头连接
- **状态显示区** (y=168..340): 左侧 4x4 state matrix + 右侧 round key matrix，16 字节以 hex 显示，变化字节高亮黄色
- **底部状态栏** (y=348..380): Round x/10, Stage name, Cycles, 对应 RISC-V 指令名
- **操作提示** (y=388..420): 按键说明

### 2.2 SHA-256 布局

```
+================================================================+
|  SHA-256 Compression Function     [Q] Quit  [R] Reset          |
+================================================================+
|                                                                 |
|  Input Block: 61626380 00000000 ... 00000018                   |
|  Hash: H0..H7 = 6A09E667 BB67AE85 ... 5BE0CD19                |
|                                                                 |
|  +--------+   +-------+   +-------+   +-------+   +-------+   |
|  | W[t]   |-->| Sigma1|-->|  Ch   |-->|  T1   |-->| h +=  |   |
|  | sched  |   | rotr  |   | e&f   |   | sum   |   | T1    |   |
|  +--------+   +-------+   +-------+   +-------+   +-------+   |
|       |                                                  ^     |
|       v                                                  |     |
|  +--------+   +-------+   +-------+   +-------+          |     |
|  | W[t]   |-->| Sigma0|-->|  Maj  |-->|  T2   |---------+     |
|  | extend |   | rotr  |   | a&b   |   | sum   |                |
|  +--------+   +-------+   +-------+   +-------+                |
|                                                                 |
|  Round 7 / 64    W[7] = 0x700C0A39    Cycles: 18,450          |
|  a=5BE0CD19 b=... h=3C6EF372                                  |
|                                                                 |
|  [Space] Step  [A] Auto  [P] Pause  [<-][->] Goto Round       |
+================================================================+
```

SHA-256 布局与 AES 类似，但展示压缩函数的 8 个工作变量 (a..h) 和消息调度 (W[t])。由于有 64 轮且画面空间有限，每轮只更新高亮变化的变量。

### 2.3 配色方案

| 元素 | 颜色 | RGB332 | 说明 |
|------|------|--------|------|
| 活跃阶段框 | 绿色 | `0x1C` (FB_GREEN) | 当前正在执行的操作 |
| 已完成阶段 | 橙色 | `0xF8` (FB_ORANGE) | 本轮已执行完的操作 |
| 待执行阶段 | 灰色 | `0x49` (FB_DKGRAY) | 本轮尚未执行的操作 |
| 数据流箭头 | 黄色 | `0xFC` (FB_YELLOW) | 阶段间的数据流 |
| 状态变化字节 | 黄色高亮 | `0xFC` (FB_YELLOW) bg | state matrix 中本轮变化的字节 |
| 状态未变化 | 白色 | `0xFF` (FB_WHITE) | state matrix 中未变化的字节 |
| 指令标注 | 青色 | `0x1F` (FB_CYAN) | 对应的 RISC-V 指令名 |
| 背景 | 深蓝灰 | `0x12` (FB_TEAL) 渐变 | Win 3.0 风格背景 |
| 框图边框 | 浅灰 | `0xDB` (FB_LTGRAY) | 阶段框/状态框边框 |
| 轮进度条 | 绿色/灰色 | 渐变 | 底部 10 格进度条 |

### 2.4 动画与交互

#### 步进模式

```
用户按 [Space] -> 前进一个 micro-step (SubBytes/ShiftRows/MixColumns/AddRoundKey)
用户按 [A]     -> 自动播放 (每 step 间隔 ~500ms，可调)
用户按 [P]     -> 暂停自动播放
用户按 [<-]    -> 回退到上一轮 (重新从初始状态计算到目标轮)
用户按 [->]    -> 跳到下一轮 (同样重新计算)
用户按 [R]     -> 完全重置
用户按 [Q]     -> 退出可视化
```

#### 状态机

```
IDLE -> (load key/plaintext) -> AES_KEY_EXPAND -> AES_ROUND(1) -> ... -> AES_ROUND(10) -> DONE
                                                                  -> SHA_ROUND(1) -> ... -> SHA_ROUND(64) -> DONE
```

每个 AES_ROUND 内部有 4 个 micro-step:
```
AES_ROUND(r):
  step 0: SubBytes   -- 高亮 SubBytes 框
  step 1: ShiftRows  -- 高亮 ShiftRows 框，SubBytes 变橙色
  step 2: MixColumns -- 高亮 MixColumns 框 (最后一轮跳过)
  step 3: AddRoundKey -- 高亮 AddRoundKey 框，更新 state，前进到 r+1
```

每个 SHA_ROUND 内部有 1 个 step (一轮就是一次压缩迭代):
```
SHA_ROUND(t):
  step 0: 压缩迭代 -- 计算新的 a..h，更新 W[t]，高亮变化变量
```

#### 自动播放速度

- 默认 500ms/step (AES) 或 200ms/step (SHA，因 64 轮太多)
- 上/下方向键调速 (100ms ~ 2000ms)
- 速度显示在状态栏

---

## 3. 实现步骤

### 3.1 文件结构与模块划分

```
sw/app/de2shell/
  crypto_viz.h          -- 可视化接口声明
  crypto_viz_aes.h      -- AES 可视化内部类型 (与 crypto_viz.c 共用)
  crypto_viz_aes.c      -- AES-128 逐步计算 + 渲染
  crypto_viz_sha.h      -- SHA-256 可视化内部类型
  crypto_viz_sha.c      -- SHA-256 逐步计算 + 渲染
  crypto_viz_common.c   -- 共享渲染原语 (框图、箭头、状态矩阵)
  gfx.c                 -- (已有) 基本图元
  gfx.c 新增:           -- gfx_rounded_rect, gfx_arrow, gfx_text_hex_cell
```

### 3.2 crypto_viz.h -- 顶层接口

```c
#ifndef CRYPTO_VIZ_H
#define CRYPTO_VIZ_H

#include <stdint.h>
#include "fb_hal.h"

/* 可视化算法类型 */
typedef enum {
    CVIZ_NONE = 0,
    CVIZ_AES128_ENC,
    CVIZ_AES128_DEC,
    CVIZ_SHA256
} cviz_algo_t;

/* 全局状态 */
typedef struct {
    cviz_algo_t algo;          /* 当前算法 */
    int         running;       /* 是否在运行 */
    int         auto_play;     /* 自动播放开关 */
    uint32_t    auto_delay_ms; /* 自动播放间隔 (ms) */

    /* AES 状态 */
    uint8_t     aes_key[16];
    uint8_t     aes_input[16];
    uint8_t     aes_state[16]; /* 当前 128-bit state */
    uint8_t     aes_prev[16];  /* 上一步 state (用于检测变化字节) */
    uint32_t    aes_rk[44];    /* 扩展密钥 */
    int         aes_round;     /* 当前轮次 0..10 */
    int         aes_step;      /* 当前微步骤 0..3 */

    /* SHA-256 状态 */
    uint8_t     sha_input[64]; /* 当前 512-bit 输入块 */
    uint32_t    sha_h[8];      /* 工作变量 */
    uint32_t    sha_prev_h[8]; /* 上一步工作变量 */
    uint32_t    sha_w[64];     /* 消息调度 */
    int         sha_round;     /* 当前压缩轮次 0..63 */
    int         sha_block_idx; /* 当前处理的块索引 */
    uint32_t    sha_digest[8]; /* 最终哈希值 */

    /* 通用 */
    uint32_t    cycle_count;   /* 模拟周期计数 */
    uint32_t    last_tick;     /* 上次自动播放 tick */
} cviz_state_t;

/* 初始化并进入可视化主循环 */
void crypto_viz_run(cviz_algo_t algo, const uint8_t *key, int key_len,
                    const uint8_t *input, int input_len);

#endif /* CRYPTO_VIZ_H */
```

### 3.3 crypto_viz_common.c -- 共享渲染原语

此模块提供密码学可视化专用的图元，建立在 `gfx.c` 之上。

#### 3.3.1 新增 gfx.c 原语

```c
/* 圆角矩形填充 */
void gfx_rounded_rect(int x, int y, int w, int h, int r, uint8_t color);

/* 带箭头的连线: (x0,y0) -> (x1,y1) */
void gfx_arrow(int x0, int y0, int x1, int y1, uint8_t color);

/* 单个 hex 字节单元格 (宽度 FONT_W*2, 高度 FONT_H) */
void gfx_hex_cell(int x, int y, uint8_t value, uint8_t fg, uint8_t bg);

/* 进度条: n 总格数, cur 当前格 */
void gfx_progress_bar(int x, int y, int w, int h, int cur, int total,
                      uint8_t fg, uint8_t bg);
```

**gfx_rounded_rect**: 简化实现 -- 4 个角各画一个 `gfx_fill_rect`，中间矩形填充。半径 r 固定为 4px。

**gfx_arrow**: Bresenham 直线 + 末端 45 度箭头 (2 条短线)。利用已有的 `gfx_line`。

**gfx_hex_cell**: 调用 `gfx_fill_rect` 画背景 + 两次 `gfx_char` 画 hex 高低半字节。

**gfx_progress_bar**: 填充 cur/total 比例的矩形，剩余部分灰色。

#### 3.3.2 可视化专用渲染函数

```c
/* 阶段框: 带圆角的彩色框 + 标题 + RISC-V 指令名 */
void cviz_draw_stage_box(int x, int y, int w, int h,
                         const char *title, const char *instr,
                         uint8_t border_color, uint8_t fill_color);

/* 数据流箭头: 两阶段框之间的带箭头连线 */
void cviz_draw_data_arrow(int x0, int y0, int x1, int y1, int active);

/* 4x4 状态矩阵: 16 字节 hex 显示，变化字节高亮 */
void cviz_draw_state_matrix(int x, int y, const uint8_t state[16],
                            const uint8_t prev[16]);

/* 4x4 轮密钥矩阵 */
void cviz_draw_round_key(int x, int y, const uint32_t rk[4], int round);

/* 底部状态栏 */
void cviz_draw_status_bar(int y, const char *algo_name,
                          int round, int total_rounds,
                          const char *stage_name,
                          const char *instr_name,
                          uint32_t cycles);

/* 操作提示行 */
void cviz_draw_help_bar(int y);
```

### 3.4 crypto_viz_aes.c -- AES-128 可视化

#### 3.4.1 核心设计: 分步计算

现有 `crypto_aes.c` 中的 `aes128_enc_block` 是一个完整的函数，无法中途暂停。需要一个**拆分版本**，每一步只执行一个操作并返回。

```c
/* AES 可视化步骤类型 */
typedef enum {
    AES_STEP_KEY_EXPAND = 0,
    AES_STEP_ADD_RK_INIT,
    AES_STEP_SUB_BYTES,
    AES_STEP_SHIFT_ROWS,
    AES_STEP_MIX_COLUMNS,   /* 最后一轮跳过 */
    AES_STEP_ADD_RK,
    AES_STEP_DONE
} aes_step_t;

/* 执行当前微步骤, 更新 viz->aes_state, 推进 step/round */
void cviz_aes_step(cviz_state_t *viz);

/* 获取当前步骤的中文名 */
const char *cviz_aes_step_name(aes_step_t step);

/* 获取当前步骤对应的 RISC-V 指令名 */
const char *cviz_aes_instr_name(aes_step_t step, int round);
```

`cviz_aes_step` 内部实现复用 `crypto_aes.c` 的底层函数:
- `sub_bytes()`, `shift_rows()`, `mix_columns()`, `add_round_key()` -- 这些都是 `static` 的，需要提升为非 static，或者直接在 crypto_viz_aes.c 中内联实现。

**方案选择**: 将 `crypto_aes.c` 中的 `sub_bytes`, `shift_rows`, `mix_columns`, `add_round_key`, `sbox`, `inv_sbox`, `gfmul` 提升为非 static (在 crypto.h 中声明)。这样 crypto_viz_aes.c 可以直接调用。

#### 3.4.2 布局常量

```c
#define AES_LAYOUT_X      16
#define AES_LAYOUT_Y      32
#define AES_LAYOUT_W      608
#define AES_LAYOUT_H      400

/* 流水线框位置 */
#define AES_SB_X    (AES_LAYOUT_X + 16)
#define AES_SB_Y    (AES_LAYOUT_Y + 120)
#define AES_SB_W    120
#define AES_SB_H    52

#define AES_SR_X    (AES_SB_X + AES_SB_W + 32)
#define AES_SR_Y    AES_SB_Y
#define AES_SR_W    120
#define AES_SR_H    52

#define AES_MC_X    (AES_SR_X + AES_SR_W + 32)
#define AES_MC_Y    AES_SB_Y
#define AES_MC_W    120
#define AES_MC_H    52

#define AES_AR_X    (AES_MC_X + AES_MC_W + 32)
#define AES_AR_Y    AES_SB_Y
#define AES_AR_W    120
#define AES_AR_H    52

/* 状态矩阵位置 */
#define AES_STATE_X  (AES_LAYOUT_X + 16)
#define AES_STATE_Y  (AES_SB_Y + AES_SB_H + 24)
#define AES_RK_X     (AES_STATE_X + 280)
#define AES_RK_Y     AES_STATE_Y
```

#### 3.4.3 渲染流程

每次画面刷新 (`cviz_aes_render`) 执行:
1. `gfx_clear(FB_TEAL)` -- 清屏为深蓝背景
2. `gfx_window_frame(0, 0, 640, 24, "AES-128 ECB Encryption", 1)` -- 标题栏
3. `gfx_text(16, 32, "Key: ...", FB_WHITE, 0xFF)` -- 输入信息
4. 画 4 个阶段框 -- 根据 `viz->aes_step` 决定哪个高亮
5. 画 3 条数据流箭头 (SB->SR, SR->MC, MC->AR)
6. 画 state matrix (对比 prev 检测变化字节)
7. 画 round key matrix
8. 画状态栏 (Round x/10, Stage, Cycles, Instruction)
9. 画进度条 (10 格)
10. 画操作提示

#### 3.4.4 回退/跳转实现

回退和跳转不能简单撤销 (非线性操作)，因此采用**重新计算**策略:
- 记住初始 plaintext 和扩展密钥
- 跳转到目标轮 r: 从 plaintext 重新执行 r 个完整轮次 (不含最后微步骤)
- 保存每轮的 state 快照 (10 轮 x 16 字节 = 160 字节，可接受)

```c
/* 预计算所有轮次的 state 快照 */
static uint8_t aes_snapshots[11][16]; /* snapshot[r] = round r 之后的 state */

void cviz_aes_precompute(const uint8_t pt[16], const uint32_t rk[44]) {
    uint8_t state[16];
    for (int i = 0; i < 16; i++) state[i] = pt[i];
    add_round_key(state, &rk[0]);
    for (int i = 0; i < 16; i++) aes_snapshots[0][i] = state[i];

    for (int r = 1; r <= 10; r++) {
        sub_bytes(state);
        shift_rows(state);
        if (r < 10) mix_columns(state);
        add_round_key(state, &rk[r * 4]);
        for (int i = 0; i < 16; i++) aes_snapshots[r][i] = state[i];
    }
}
```

回退时: `memcpy(viz->aes_state, aes_snapshots[target_round], 16);`

### 3.5 crypto_viz_sha.c -- SHA-256 可视化

#### 3.5.1 核心设计

SHA-256 压缩函数有 64 轮，每轮计算量大但结构统一:
```
S1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25)
ch = (e & f) ^ (~e & g)
temp1 = h + S1 + ch + K[t] + W[t]
S0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22)
maj = (a & b) ^ (a & c) ^ (b & c)
temp2 = S0 + maj
h = g; g = f; f = e; e = d + temp1
d = c; c = b; b = a; a = temp1 + temp2
```

可视化时，每轮只显示 a..h 中的变化值 (每轮所有 8 个变量都会变化) 和 W[t]。

#### 3.5.2 布局

与 AES 类似但更紧凑:
- 顶部 8 个工作变量 (a..h) 以水平排列显示
- 中部消息调度 W[t] 显示当前值
- 底部 64 轮进度条 (每格代表一轮，可以画 64 个 8x6 的小方格)
- 每个变化变量高亮

#### 3.5.3 分步实现

复用 `crypto_sha.c` 中的 `sha256_transform`，但拆成逐轮版本:

```c
void cviz_sha_step(cviz_state_t *viz);
const char *cviz_sha_instr_name(int round);
```

预计算方案与 AES 类似: 预计算 64 个快照 (每快照 8 个 uint32_t = 32 字节，共 2048 字节)。

### 3.6 与现有 crypto.c 的集成

#### 3.6.1 提升 static 函数可见性

修改 `sw/app/crypto_cli/crypto_aes.c`:
- `sub_bytes` -> `aes_sub_bytes` (非 static, 在 crypto.h 声明)
- `shift_rows` -> `aes_shift_rows`
- `mix_columns` -> `aes_mix_columns`
- `inv_sub_bytes` -> `aes_inv_sub_bytes`
- `inv_shift_rows` -> `aes_inv_shift_rows`
- `inv_mix_columns` -> `aes_inv_mix_columns`
- `add_round_key` -> `aes_add_round_key`
- `sbox` -> `aes_sbox` (const, 声明为 extern const)
- `inv_sbox` -> `aes_inv_sbox`
- `gfmul` -> `aes_gfmul`

修改 `sw/app/crypto_cli/crypto_sha.c`:
- `sha256_transform` -> 拆分版本 `sha256_transform_step` (逐轮)
- `rotr32`, `bswap32` -> 提升为公共 (或保留 static 内联，在 crypto_viz_sha.c 中重新定义)

修改 `sw/app/crypto_cli/crypto.h`:
- 新增上述函数声明

**注意**: `crypto_aes.c` 和 `crypto_sha.c` 位于 `sw/app/crypto_cli/`，被 de2shell 和 de2shell_rtos 共享。提升可见性不影响现有功能。

#### 3.6.2 de2shell 集成 (V2 frozen, 仅 local build)

在 de2shell 的 `win30_desk.c` 中，"Crypto" 图标已存在 (icon_names[2])。点击后:
1. 进入 AES 可视化 (使用 NIST FIPS-197 默认测试向量)
2. 可视化运行中按 Q 返回桌面

由于 de2shell 已冻结且 V2 不支持像素模式，此集成仅限 `make local`。

#### 3.6.3 de2shell_rtos 集成 (V3 目标)

在 de2shell_rtos 的 shell 中添加命令:
```
crypto_viz aes enc <key> <pt>   -- AES-128 加密可视化
crypto_viz sha256 <hex-msg>     -- SHA-256 可视化
```

调用 `crypto_viz_run()` 进入可视化模式。可视化占用整个像素帧缓冲，退出后恢复文本模式。

### 3.7 依赖关系

```
crypto_viz_aes.c  --> crypto.h (aes_sub_bytes, aes_shift_rows, ...)
crypto_viz_sha.c  --> crypto.h (sha256 相关)
crypto_viz_common.c --> gfx.h, gfx_font.h
crypto_viz_main.c   --> fb_hal.h, ps2_decoder.h (键盘输入), crypto_viz.h
```

### 3.8 开发顺序

| 步骤 | 内容 | 依赖 | 估计时间 |
|------|------|------|----------|
| 1 | 修改 crypto_aes.c/crypto_sha.c: 提升 static 函数 | 无 | 1h |
| 2 | 修改 crypto.h: 新增公开声明 | 步骤 1 | 0.5h |
| 3 | gfx.c 新增 rounded_rect/arrow/hex_cell/progress_bar | 无 | 2h |
| 4 | crypto_viz_common.c: 共享渲染原语 | 步骤 3 | 2h |
| 5 | crypto_viz_aes.c: AES 分步计算 + 渲染 | 步骤 1, 4 | 4h |
| 6 | crypto_viz_sha.c: SHA 分步计算 + 渲染 | 步骤 2, 4 | 3h |
| 7 | crypto_viz_main.c: 主循环 + 键盘处理 + 自动播放 | 步骤 5, 6 | 2h |
| 8 | de2shell local build 集成 (win30_desk.c 点击入口) | 步骤 7 | 1h |
| 9 | SDL2 本地测试: AES 10 轮完整步进 | 步骤 8 | 1h |
| 10 | SDL2 本地测试: SHA-256 64 轮步进 | 步骤 9 | 1h |
| 11 | de2shell_rtos 集成: shell 命令 + 像素模式切换 | 步骤 7 | 1h |
| 12 | FPGA 像素模式板上测试 | 步骤 11 | 1h |
| | **总计** | | **~19.5h** |

### 3.9 makefile 修改

`sw/app/de2shell/makefile` (local build) -- 需要将 crypto_viz 相关源文件加入 `local` 目标的编译列表:

```makefile
# LOCAL_BUILD 编译额外源文件 (像素模式相关)
VIZ_SRC = fb_hal.c gfx.c gui.c gui_widgets.c crypto_viz_common.c \
          crypto_viz_aes.c crypto_viz_sha.c win30_desk.c
```

`sw/app/de2shell_rtos/makefile` -- 需要类似修改。

### 3.10 内存占用估算

| 数据 | 大小 | 说明 |
|------|------|------|
| cviz_state_t | ~380 bytes | 运行时状态 |
| aes_snapshots[11][16] | 176 bytes | AES 轮次快照 |
| sha_snapshots[64][32] | 2048 bytes | SHA 轮次快照 |
| 帧缓冲 (SDRAM) | 307,200 bytes | 像素帧缓冲 (固定开销) |
| 代码 (ROM) | ~4-6 KB | 估算: 渲染 + 计算 |
| **总计额外 RAM** | **~2.6 KB** | 可接受 |

---

## 4. 验收标准

### 4.1 AES-128 加密可视化

- 正确使用 NIST FIPS-197 Appendix B 测试向量:
  - Key: `2b7e151628aed2a6abf7158809cf4f3c`
  - Plaintext: `6bc1bee22e409f96e93d7e117393172a`
  - Ciphertext: `3ad77bb40d7a3660a89ecaf32466ef97`
- 10 轮均可步进，每轮 4 个微步骤清晰区分
- state matrix 中变化字节正确高亮
- 最终输出与 `aes128_enc_block` 结果一致

### 4.2 SHA-256 可视化

- 正确使用 FIPS-180-4 测试向量:
  - Input: `abc` (hex: `616263`)
  - Digest: `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`
- 64 轮可步进，工作变量实时更新
- 最终哈希值与 `sha256_hash` 结果一致

### 4.3 渲染质量

- 阶段框清晰可辨，高亮/灰色区分明显
- 数据流箭头指向正确
- 文字不溢出框边界
- 进度条正确反映当前轮次
- 背景无闪烁 (SDL2: 使用 `fb_present` 双缓冲)

---

## 验收表

| 编号 | 验收项 | 状态 |
|------|--------|------|
| V3P3B.S1.1 | AES-128 加密 10 轮完整步进可视化，每轮 SubBytes/ShiftRows/MixColumns/AddRoundKey 四阶段框图正确显示 | |
| V3P3B.S1.2 | AES state matrix (4x4 字节) 实时更新，变化字节黄色高亮，轮密钥矩阵同步显示 | |
| V3P3B.S1.3 | SHA-256 压缩函数 64 轮逐步可视化，8 个工作变量 (a..h) 和消息调度 W[t] 实时更新 | |
| V3P3B.S1.4 | 轮计数器 (AES: x/10, SHA: x/64) 和周期计数器正确显示 | |
| V3P3B.S1.5 | 手动步进 (Space 键) 和自动播放 (A 键 + P 键暂停) 均正常工作 | |
| V3P3B.S1.6 | 活跃阶段绿色高亮、已完成阶段橙色、待执行阶段灰色的三色配色方案正确 | |
| V3P3B.S1.7 | SDL2 本地构建 (`make local`) 渲染正确，画面无闪烁，帧缓冲双缓冲生效 | |
| V3P3B.S1.8 | FPGA 像素模式 (SDRAM 帧缓冲) 渲染正确，与 SDL2 版本布局一致 | |
| V3P3B.S1.9 | NIST FIPS-197 AES 测试向量通过 (输入/输出匹配) | |
| V3P3B.S1.10 | FIPS-180-4 SHA-256 测试向量通过 (输入/哈希匹配) | |
