# AM Contract Tests

这些测试用于从 AM 外部验证 AM contract，不在 `abstract-machine/` 内部加入断言或改变 guest 正常 flow。每个 contract 尽量只覆盖一个子系统，失败时通过固定阶段名定位问题。

## Usage

批量运行：

```sh
make -C am-apps/contracts ARCH=riscv32-nemu run
make -C am-apps/contracts ARCH=riscv32e-npc run
make -C am-apps/contracts ARCH=riscv32e-ysyxsoc run
```

运行单个或部分 contract：

```sh
make -C am-apps/contracts ARCH=riscv32e-npc ALL=10-cte-yield run
make -C am-apps/contracts ARCH=riscv32e-ysyxsoc ALL='14-gpu-config 15-gpu-fbdraw-smoke' run
make -C am-apps/contracts ARCH=riscv32e-ysyxsoc ALL=14-gpu-config,15-gpu-fbdraw-smoke run
make -C am-apps/contracts/10-cte-yield ARCH=riscv32e-npc run
```

不设置 `ALL` 时，顶层 Makefile 会按 `ARCH` 运行默认自动集合；设置 `ALL` 时，只运行指定 contract。

日志位置：

```text
am-apps/contracts/build/contract-<arch>-<contract>.log
```

需要人工观察或输入的 IOE 诊断测试不进入 contracts 默认门禁，统一放在 `am-apps/ioe/`：

```sh
make -C am-apps/ioe/keyboard ARCH=riscv32e-ysyxsoc run
make -C am-apps/ioe/gpio ARCH=riscv32e-ysyxsoc run
```

## Result Protocol

每个自动 contract 都输出：

```text
CONTRACT <id> BEGIN
CONTRACT <id> PASS
```

失败时输出：

```text
CONTRACT <id> FAIL <stage>
```

`run-contracts.sh` 同时检查命令退出状态和 `PASS` token。`00-trm-putch-halt` 额外检查 `TRM_PUTCH_TOKEN`；`04-klib-stdio` 额外检查 `KLIB_PRINTF_TOKEN`；`13-uart-tx` 在非 SKIP 时额外检查 `UART_TX_TOKEN`。

## 自动可验证测试

| ID | Contract | Primary coverage | Platforms |
|---|---|---|---|
| 00 | `trm-putch-halt` | `_trm_init -> main`、`putch` 可见输出、`halt(0)` good trap | nemu, npc, ysyxsoc |
| 01 | `sections-data-bss` | `.data` 初值、`.bss` 清零、小栈读写 | nemu, npc, ysyxsoc |
| 02 | `heap-window` | `heap.start/end`、heap 头/中/尾小窗口可写 | nemu, npc, ysyxsoc |
| 03 | `klib-string` | `string.c` 全部公开函数：字符串复制/拼接/比较和内存操作 | nemu, npc, ysyxsoc |
| 04 | `klib-stdio` | `stdio.c` 全部公开函数：`printf/sprintf/snprintf/vsprintf/vsnprintf` 和核心格式 | nemu, npc, ysyxsoc |
| 05 | `klib-stdlib` | `stdlib.c` 全部公开函数：`atoi/abs/rand/srand/malloc/free` 的 AM 简化语义 | nemu, npc, ysyxsoc |
| 06 | `libgcc-rv32e` | RV32E 64-bit `mul/div/rem/shift` helper 链接和结果 | npc, ysyxsoc |
| 07 | `ioe-config` | `ioe_init` 和 TIMER/INPUT/UART/GPU/GPIO config LUT | npc, ysyxsoc |
| 08 | `timer-uptime` | `AM_TIMER_UPTIME` 非递减并增长 | nemu, npc, ysyxsoc |
| 09 | `timer-rtc` | RTC 字段范围和两次读取不倒退 | npc, ysyxsoc |
| 10 | `cte-yield` | `cte_init`、`yield()`、`EVENT_YIELD`、trap 返回 | nemu, npc, ysyxsoc |
| 11 | `cte-syscall` | 普通 `ecall`、`EVENT_SYSCALL`、`GPR1` 判定、`mepc+4` | nemu, npc, ysyxsoc |
| 12 | `cte-kcontext` | `kcontext`、Context ABI、`trap.S` 使用 handler 返回的新 context | nemu, npc, ysyxsoc |
| 13 | `uart-tx` | `AM_UART_CONFIG`、`AM_UART_TX` 可见输出 token | npc skip, ysyxsoc |
| 14 | `gpu-config` | GPU present、尺寸；ysyxsoc 要求 640x480 | ysyxsoc |
| 15 | `gpu-fbdraw-smoke` | 四角小色块绘制、sync、不崩溃；不验证肉眼画面 | ysyxsoc |
| 16 | `input-idle` | 空闲键盘读取不挂死、keycode 范围合法 | ysyxsoc |
| 17 | `ysyxsoc-layout` | SSBL/SRAM、Flash LMA、SDRAM data/bss/heap、SP、heap 写读 | ysyxsoc |
| 18 | `gpio-config` | GPIO present、LED/SEG/SW 基础路径 | ysyxsoc |

这些测试由 `run-contracts.sh` 自动判断结果。判断依据是 simulator 返回状态、`CONTRACT <id> PASS` token，以及少数测试的额外输出 token。它们适合作为快速回归和定位入口。

## Correctness Mapping

| Exam flow | Contracts |
|---|---|
| NEMU 启动 RT-Thread | 00, 01, 02, 03, 04, 05, 08, 10, 11, 12 |
| NPC 启动 RT-Thread 和 shell | 00, 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13 |
| ysyxSoC 启动 RT-Thread | NPC 集合加 14, 15, 16, 17, 18 |
| RT-Thread 上运行 microbench | 03, 04, 05, 06, 08 |
| 贪吃蛇/NVBoard | 14, 15, 16 加 `am-apps/ioe/gpu`；具体按键操作由贪吃蛇/打字游戏本身验证 |

## Notes

- 自动 contract 使用 `putch + halt` 协议，不使用 `printf/assert` 作为失败基础设施。
- `riscv32-nemu` 默认不跑 `09-timer-rtc`，避免 NEMU RTC stub 污染定位。
- GPU/input/GPIO 无法完全自动判断真实可见性，因此自动 smoke 留在 contracts，人工诊断测试放在 `am-apps/ioe/`。
- bug 注入验证应使用临时 patch，验证后立即恢复，再重跑对应 contract。
