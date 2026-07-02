# AM IOE Diagnostic Tests

这些测试用于人工观察和交互诊断 IOE 路径，不作为自动门禁。自动可判定的 IOE smoke 仍在 `am-apps/contracts/` 中。

## Usage

每个测试都是独立 AM app，按需进入对应目录运行：

```sh
make -C am-apps/ioe/keyboard ARCH=riscv32e-ysyxsoc run
make -C am-apps/ioe/uart ARCH=riscv32e-ysyxsoc run
make -C am-apps/ioe/timer ARCH=riscv32e-ysyxsoc run
make -C am-apps/ioe/gpu ARCH=riscv32e-ysyxsoc run
make -C am-apps/ioe/gpio ARCH=riscv32e-ysyxsoc run
```

只构建镜像时，把目标改成 `image`：

```sh
make -C am-apps/ioe/timer ARCH=riscv32e-npc image
```

## Tests

| Test | Main diagnosis | Human action / observation |
|---|---|---|
| `keyboard` | `UART_CONFIG/RX` 和 `INPUT_CONFIG/KEYBRD` 双通道输入诊断 | 按 WASD、方向键、Enter、Esc；UART 输入字符会和 KBD 事件分开打印 |
| `uart` | `AM_UART_CONFIG/TX/RX` 单独诊断 | 观察 TX token；若支持 RX，输入字符并观察 char/hex 回显 |
| `timer` | `AM_TIMER_CONFIG/UPTIME/RTC` 可观察时间诊断 | 每秒观察 uptime delta、RTC 字段；Esc 或 30 轮退出 |
| `gpu` | `AM_GPU_CONFIG/FBDRAW/sync` 分阶段可视诊断 | 按终端 `STEP` 对照 `am-apps/ioe/gpu/reference/*.png`，观察背景、边框、渐变、棋盘、红十字和四色角块 |
| `gpio` | `AM_GPIO_CONFIG/LED/SW/SEG` 分阶段诊断 | 观察 LED 跑马、SEG 计数/固定 pattern/marchid/SW 镜像；设置 SW=`0xec73` 退出 |

## Diagnostic Notes

- `keyboard` 故意继承 `am-tests k` 的 UART/KBD 双输入反馈能力，但输出阶段更明确。
- `uart` 用来把 UART TX/RX 问题从 keyboard 测试中拆开。
- `timer` 替代 `am-tests t` 的无限打印，增加 delta/RTC 状态提示。
- `gpu` 关注视觉正确性，不替代 `contracts/15-gpu-fbdraw-smoke` 的自动 no-crash smoke；参考图可用 `python3 am-apps/ioe/gpu/reference/gen_gpu_reference.py` 重新生成。
- `gpio` 合并旧 `gpio-ioe-test` 和 contracts manual GPIO，并保留 `GPIO_PASSCODE=0xec73`。
