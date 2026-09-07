# 本地迭代评估流

每轮 RTL 优化后使用下面两个正式入口。两个入口均针对当前 checkout 的
`npc/build/ysyx_<stuid>.v`；默认产生的日志和临时 checkout 都位于被
`.gitignore` 忽略的 `.tmp/` 下。

## 1. 功能验证：三个程序 + CI 面积

入口：`verify_functional.py`

它按 `ARCH=riscv32e-ysyxsoc` 执行仓库原有的 `run` 目标，因此三个程序都使用
ysyxsoc 版本的 Verilator 仿真：

- `rt-thread-am`：核对 RT-Thread banner、初始化成功、`Hello RISC-V!` 和板级
  UART 自动送入的 shell 命令输出。它不会自行退出；全部 marker 出现后脚本
  立即停止该次仿真，若一直没有出现则由 `--rtthread-timeout` 判失败。
- `cpu-tests(ALL)`：使用 `cpu-tests/Makefile` 默认发现的全部 `tests/*.c`，核对
  最终 test list、每项 `[test] PASS`、每个测试的 `HIT GOOD TRAP` 和顶层返回码。
- `hello`：传入 `mainargs=ysyx_<stuid>`，核对 `Hello, AbstractMachine!`、完整
  的 `mainargs` 输出和 `HIT GOOD TRAP`。

最后运行 CI workflow 对应的新旧两个 `yosys-sta` 面积 flow；新 flow 限制从
workflow 读取，当前通常为 `16500`，旧 flow 限制通常为 `25000`，任一通过即为
CI hard gate PASS。

```bash
python3 scripts/verify_functional.py --refresh-verilog
```

默认超时为：CI 面积 900 秒、rt-thread 120 秒、cpu-tests 900 秒、hello 120 秒。
可分别用 `--ci-timeout`、`--rtthread-timeout`、`--cpu-tests-timeout` 和
`--hello-timeout` 调整。结果 JSON 和各程序日志在输出的 `run_root` 中。

## 2. 评分：train IPC + ECC Fmax

入口：`score_cpu.py`

脚本先确认 CI 面积 hard gate，然后并行启动：

1. `am-kernels/benchmarks/microbench` 的
   `make ARCH=riscv32e-ysyxsoc mainargs=train run`，从 ysyxsoc NPC 的最终统计
   读取 IPC，并要求 `MicroBench PASS`；
2. ECC/ECOS-Studio 项目的 `syn_sta` flow，只读取综合阶段的 STA 报告。

评分公式为：

```text
score = train_IPC * min(ECC_Fmax_MHz, 1000)
```

只有 CI 面积通过、train 正确完成且 ECC 综合 flow 成功并留下有效 STA 报告时，
iteration 才报告 PASS。评分使用综合级 Fmax；不运行、不解析 routing、RCX 或
post-route STA，也不会把物理 flow 失败后留下的报告作为回退结果。

ECC 项目的 `ecc.toml` 必须显式配置：

```toml
[flow]
preset = "syn_sta"
```

```bash
python3 scripts/score_cpu.py --refresh-verilog
```

ECC 默认使用一个新的 `score-*` run，避免覆盖上一次结果。也可以指定：

```bash
python3 scripts/score_cpu.py \
  --ecc-project .tmp/ecc-project \
  --ecc-bin .tmp/ecc-bin/ecc \
  --ecc-run-id score-manual
```

默认 train/ECC 超时分别为 1800/3600 秒，可用 `--train-timeout` 和
`--ecc-timeout` 调整。train 日志在评分 run 目录的
`microbench-train.log`，ECC 日志在对应 `runs/<run-id>/score.ecc.log`。

## CI 网表工具入口

`gen_ci_aligned_netlist.py` 不是评分入口，而是 CI 网表仿真所需的工件生成器。
它只执行 CI workflow 中旧版/回退后的 `yosys-sta` flow，输出：

```text
.tmp/ysyx_<stuid>.netlist.fixed.v
```

这里明确不使用 ECC 生成的网表。运行：

```bash
python3 scripts/gen_ci_aligned_netlist.py --refresh-verilog
```

随后把该文件作为 `NETLIST` 传给现有的
`make -C npc sim-iverilog-netlist` 流程，并使用同一 CI cache 中的仿真 cell
模型。

## 内部辅助脚本

- `eval_ci_area.py`：CI 面积评估实现；两个正式入口以 `--skip-ecc` 调用它。直接
  运行时也可以执行 ECC 综合 Fmax 评估。
- `ci_support.py`：自动复用或克隆 CI checkout 到 `.tmp/ysyx-submit-test`，不
  被 Git 跟踪。
- `flow_support.py`：功能/评分入口共用的低开销输出监测、超时和进程组收尾逻辑。
- `gen_ci_patches.py`、`gen_vscode_compile_commands.py`：与本迭代评估无关。
