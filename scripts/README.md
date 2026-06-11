# 脚本说明

这个目录放的是一些本地辅助脚本，主要用于准备 CI 所需文件，以及在本机快速做 CI 等效检查。

## `gen_ci_patches.py`

功能：
- 生成 CI 所需的 `patch/rt-thread-am/` 和 `patch/ysyxSoC/` 补丁
- 在导出 `ysyxSoC` 补丁前，先刷新 `ysyxSoC/patch/rocket-chip.patch`

用法：

```bash
cd ~/ysyx-workbench
python3 scripts/gen_ci_patches.py
```

如果只想生成其中一个项目的补丁：

```bash
python3 scripts/gen_ci_patches.py --project rt-thread-am
python3 scripts/gen_ci_patches.py --project ysyxSoC
```

输出位置：
- `patch/rt-thread-am/0001-*.patch`
- `patch/ysyxSoC/0001-*.patch`

## `eval_ci_area.py`

功能：
- 在本机执行一套与当前 CI `yosys-sta` 流程等效的面积评估
- 自动从 CI workflow 中读取 `yosys-sta` 分支、`revert` 提交和面积门限
- 同时跑新 flow 和旧 flow，并给出最终的 CI 通过/失败结论

默认假设：
- `ysyx-workbench` 就是当前 `scripts/` 所在仓库根目录
- CI 仓库默认在同级目录 `~/ysyx-submit-test`
- Yosys 默认使用 `~/oss-cad-suite/bin/yosys`

用法：

```bash
cd ~/ysyx-workbench
python3 scripts/eval_ci_area.py
```

如果 CI 仓库不在默认位置，可以手动指定：

```bash
python3 scripts/eval_ci_area.py --ci-repo ~/ysyx-submit-test
```

如果希望保留运行目录并导出 JSON 摘要：

```bash
python3 scripts/eval_ci_area.py \
  --keep-run-dir \
  --json-out /tmp/ysyx-ci-area.json
```

常用参数：
- `--workbench`：指定 workbench 根目录
- `--npc-home`：指定 NPC 目录
- `--stuid`：手动指定学号，覆盖从 `Makefile` 自动解析的结果
- `--yosys-bin`：指定使用的 Yosys 可执行文件
- `--cache-dir`：指定 `yosys-sta` 本地缓存目录
