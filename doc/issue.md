# DE2Extra 问题记录

> 本项目完全出于个人兴趣，不计入课程成绩。记录问题是为了写报告时有素材可引用。
> VHDL 相关的问题重点标注。

## 状态标记

- ☐ 待解决
- ✅ 已解决
- ⏸ 暂缓 (不影响进度)
- ❌ 放弃 (有替代方案)

---

## VHDL 语法与 Quartus 问题

| # | 日期 | 问题 | 原因 | 解决 | Phase |
|---|---|---|---|---|---|
| 1 | 2026-05-xx | Cyclone IV 不允许对 `out` 端口做条件信号赋值 | Quartus Lite 限制，VHDL-93 不允许直接读取 out 端口 | 内部信号中转，输出端口赋值 | 0 |

---

## 时序与时钟问题

| # | 日期 | 问题 | 原因 | 解决 | Phase |
|---|---|---|---|---|---|
| 2 | 2026-05-22 | SDRAM hold timing 违例 TNS=-0.804ns | 50MHz→100MHz CDC 侧 hold 裕量不足，信号直接从 WB 主端跳到 100MHz 同步器 | 50MHz 侧加 `p_cdc_pref` 前置寄存器，所有 WB 信号先在 50MHz 域打一拍再进入 CDC 同步器 | 1 |

---

## 工具链问题

| # | 日期 | 问题 | 原因 | 解决 | Phase |
|---|---|---|---|---|---|
| 3 | 2026-05-xx | riscv-gcc 编译需要完整 march 字符串 | Zk* 扩展需要逐个列出 | `-march=rv32imczkne_zknd_zknh_...` | 2a |

---

## 综合/上板问题

| # | 日期 | 问题 | 原因 | 解决 | Phase |
|---|---|---|---|---|---|
| 4 | 2026-05-23 | SDRAM 自检一开始即 `Load access fault` | `sdram_ctrl` 对 NEORV32 XBUS 连续请求的 CDC / 应答握手不稳，事务丢失 | 将请求/应答改为 toggle 型跨时钟握手，并把 `ack` 延后到控制器真正空闲时返回 | 1 |
| 5 | 2026-05-23 | `TEST2` bulk 读回出现 `0x3d...` / `0xc2...` 垃圾值 | `ack` 已同步回 CPU 域，但 32-bit 读数据没有做 100MHz→50MHz CDC | 为读数据增加持有寄存器和两级同步，再输出到 `wb_dat_o` | 1 |
| 6 | 2026-05-23 | `TEST3` checkerboard 只差 1 bit (`0xAAAAAAAA -> 0xAAAA2AAA`) | 外部 `DRAM_CLK` 相对控制器内部采样点还有轻微相位偏差 | 调整 `altpll_50_100.vhd` 中 `SDRAM_CLK_SHIFT_PS`，最终稳定值为 `1560ps` | 1 |
| 7 | 2026-05-24 | NTT `ntt_sdf.vhd` 综合失败 | VHDL synthesis errors 未详细分析 | 硬件禁用（data/ack 接地），C 驱动完成 LOCAL_BUILD 验证 | V3 |
| 8 | 2026-05-24 | de2os ICACHE 开启后无输出 | 连续 SDRAM 取指下的 CDC 残余风险（ICACHE line refill 连续 8 次 locked single-read） | `ICACHE_EN=false` 作为稳定基线，性能回补留待后续 | V3 |

---

## 软件问题

| # | 日期 | 问题 | 原因 | 解决 | Phase |
|---|---|---|---|---|---|
| 9 | 2026-05-23 | `build.sh` 中 `make clean all image` 单次调用导致 `build/*.d` 目录缺失 | `clean` 删 `build/` 后，后续目标不触发 mkdir | 分步执行 `make clean; mkdir -p build; make image` | 3 |
| 10 | 2026-05-24 | de2shell IMEM 镜像 ~39KB 超过旧 32KB 配置 | 固件持续增长 | 硬件 IMEM 改为 64KB | 3 |
| 11 | 2026-05-24 | Exp10 IR 码表与遥控器物理键名不一致 | CH 遥控器键序 ≠ 实验遥控器表 6-16 | 统一以 Exp10 表 6-16 为准, 修复 dashboard.c/main.c 映射 | 3 |
