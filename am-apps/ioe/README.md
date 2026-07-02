# AM IOE Diagnostic Tests

这些测试用于人工观察和交互诊断 IOE 路径，不作为自动门禁。自动可判定的 IOE smoke 仍在 `am-apps/contracts/` 中。

## Usage

默认运行全部人工 IOE 诊断测试：

```sh
make -C am-apps/ioe ARCH=riscv32e-ysyxsoc run
```

运行指定测试，`ALL` 支持空格或逗号分隔：

```sh
make -C am-apps/ioe ARCH=riscv32e-ysyxsoc ALL=keyboard-visible run
make -C am-apps/ioe ARCH=riscv32e-ysyxsoc ALL='gpu-pattern gpio-visible' run
make -C am-apps/ioe ARCH=riscv32e-npc ALL=timer-visible,uart-visible image
```

## Tests

| Test | Main diagnosis | Human action / observation |
|---|---|---|
| `keyboard-visible` | `UART_CONFIG/RX` 和 `INPUT_CONFIG/KEYBRD` 双通道输入诊断 | 按 WASD、方向键、Enter、Esc；UART 输入字符会和 KBD 事件分开打印 |
| `uart-visible` | `AM_UART_CONFIG/TX/RX` 单独诊断 | 观察 TX token；若支持 RX，输入字符并观察 char/hex 回显 |
| `timer-visible` | `AM_TIMER_CONFIG/UPTIME/RTC` 可观察时间诊断 | 每秒观察 uptime delta、RTC 字段；Esc 或 30 轮退出 |
| `gpu-pattern` | `AM_GPU_CONFIG/FBDRAW/sync` 可视诊断 | 观察白边框、红十字、顶部渐变、棋盘、四色角块；Esc 退出 |
| `gpio-visible` | `AM_GPIO_CONFIG/LED/SW/SEG` 分阶段诊断 | 观察 LED 跑马、SEG 固定值和 marchid；设置 SW=`0xec73` 退出 |

## Diagnostic Notes

- `keyboard-visible` 故意继承 `am-tests k` 的 UART/KBD 双输入反馈能力，但输出阶段更明确。
- `uart-visible` 用来把 UART TX/RX 问题从 keyboard 测试中拆开。
- `timer-visible` 替代 `am-tests t` 的无限打印，增加 delta/RTC 状态提示。
- `gpu-pattern` 关注视觉正确性，不替代 `contracts/15-gpu-fbdraw-smoke` 的自动 no-crash smoke。
- `gpio-visible` 合并旧 `gpio-ioe-test` 和 contracts manual GPIO，并保留 `GPIO_PASSCODE=0xec73`。
