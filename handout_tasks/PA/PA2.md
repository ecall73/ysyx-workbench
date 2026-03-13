
---
# PA2 实验报告

## 程序是个状态机：YEMU加法程序分析
YEMU模拟器运行的加法程序可以看作一个有限状态机。每个状态由以下变量共同决定：
- PC（程序计数器）
- R[0..3]（寄存器组）
- M[0..15]（内存）
- halt（结束标志）

状态机的转移过程如下：
1. 取指：当前状态由PC决定，从内存M[pc]取出一条指令。
2. 译码：根据操作码（op）判断指令类型，解析操作数（rs, rt, addr）。
3. 执行：根据指令类型修改寄存器或内存内容。
4. 更新PC：PC加1，进入下一个状态。
5. 检查halt：如遇非法指令或程序结束，halt置1，状态机停止。

以加法程序为例，状态机的每一步如下：
- 初始状态：PC=0，R全部为0，M初始化为加法程序，halt=0。
- 每执行一次exec_once()，状态机转移到下一个状态。
- 最终状态：M[7]存储了16+33的结果。

### YEMU执行一条指令的过程（RTFSC分析）
1. this.inst = M[pc]：取指令
2. switch(this.rtype.op)：译码操作码
3. 根据操作码分支：
	- mov：R[rt]=R[rs]
	- add：R[rt]+=R[rs]
	- load：R[0]=M[addr]
	- store：M[addr]=R[0]
4. pc++：更新PC
5. 如遇非法指令，halt=1

### 两者联系
YEMU的状态机和exec_once()的执行过程是等价的：
每执行一次exec_once()，状态机就转移一次。所有状态变量（PC、寄存器、内存、halt）共同决定了当前状态，指令执行过程就是状态机的转移规则。

简言之：YEMU的程序执行过程就是一个状态机的不断转移，直到halt。

## RTFSC：一条指令在NEMU中的执行过程
以RISC-V为例，NEMU执行一条指令的完整流程如下：

1. 主循环入口：`cpu_exec(n)`（src/cpu/cpu-exec.c）
	- 设置状态，调用 `execute(n)`，循环执行n条指令。
2. 单步执行：`exec_once(&s, cpu.pc)`
	- 记录当前PC，调用 `isa_exec_once(s)`（ISA相关实现，负责取指、译码、执行）。
3. 取指：`inst_fetch(vaddr_t *pc, int len)`（include/cpu/ifetch.h）
	- 通过 `vaddr_ifetch(*pc, len)` 从虚拟地址读取指令内容。
	- `vaddr_ifetch` 调用 `paddr_read(addr, len)`（src/memory/vaddr.c/paddr.c），实际从物理内存或MMIO读取。
4. 译码：在 `isa_exec_once` 内部，解析指令格式、操作码、操作数。
	- 生成Decode结构体，填充指令、操作数等信息。
5. 执行：根据译码结果，修改CPU寄存器、内存、设备状态。
	- 普通指令直接操作CPU和内存。
	- 若访问MMIO（如VGA、键盘），`paddr_read/paddr_write`会调用 `mmio_read/mmio_write`，进而触发设备模拟（如src/device/vga.c、keyboard.c等）。
6. 更新PC：`cpu.pc = s->dnpc`，进入下一条指令。
7. 设备更新：`device_update()`，周期性刷新设备状态（如VGA显示、键盘输入等）。
8. 跟踪/断点/差分测试：`trace_and_difftest(&s, cpu.pc)`，记录指令、检查断点、与参考实现对比。

每一步都对应具体代码实现，整个流程体现了“取指-译码-执行-访存/设备-更新PC-设备同步”的完整状态机转移。

## 程序如何运行：打字小游戏源码分析
打字小游戏的运行过程可以分为以下几个阶段：

1. 初始化阶段
	- 调用 `ioe_init()` 初始化设备抽象。
	- 通过 `io_read(AM_GPU_CONFIG)` 获取屏幕宽高，初始化画面和字母纹理（video_init）。
	- 清屏、准备字体数据（font.c）、初始化分数统计。

2. 主循环结构
	- 以每帧为单位循环（FPS=30），用 `io_read(AM_TIMER_UPTIME)` 控制帧率。
	- 每帧调用 `game_logic_update(current)`，负责字母生成、下落、消除、miss判定。

3. 输入处理
	- 循环读取 `io_read(AM_INPUT_KEYBRD)`，获取键盘事件。
	- 若按下ESC，调用 `halt(0)` 退出。
	- 若按下A-Z，查表（lut[]）映射为字母，调用 `check_hit()` 判定命中。
	- 命中则更新分数、字母状态（hit/wrong/miss）。

4. 状态更新
	- 字母下落、miss、消除等逻辑全部在 `game_logic_update` 内完成。
	- 每帧都可能生成新字母、处理miss、消除已命中字母。

5. 渲染流程
	- 每帧调用 `render()`，先用 `io_write(AM_GPU_FBDRAW)` 擦除上帧字母，再绘制当前所有字母。
	- 字母颜色根据状态（正常/命中/miss）切换。
	- 最后用 `io_write(AM_GPU_FBDRAW, 0, 0, NULL, 0, 0, true)` 同步刷新屏幕。
	- 分数统计通过 `printf` 输出到终端。

6. AM/NEMU协作链路
	- 游戏通过AM接口（io_read/io_write）访问设备，不直接操作硬件。
	- NEMU负责模拟MMIO设备，接收键盘事件、处理帧缓冲、响应sync信号。
	- 用户按键先被NEMU捕获，AM抽象层再将事件传递给游戏。
	- 显示刷新由NEMU VGA设备完成，sync信号触发窗口更新。

综上，打字小游戏的运行过程是“状态机驱动+设备抽象+硬件模拟”协同完成的。每一帧都经历输入采集、状态更新、画面渲染、设备同步，底层由AM和NEMU共同支撑。

## 编译与链接：inst_fetch static/inline分析
`inst_fetch` 在 nemu/include/cpu/ifetch.h 中定义为 `static inline`，其含义和编译行为如下：

1. 原始定义：`static inline`
	- static：只在当前源文件可见，不会生成外部符号。
	- inline：建议编译器将函数体直接插入调用处，避免生成多份代码。
	- 结果：每个包含该头文件的源文件都能安全使用 inst_fetch，不会有链接冲突，也不会生成多余代码。

2. 去掉 static，只保留 inline
	- inline 只建议内联，但不强制。
	- 没有 static，函数变为外部链接（external linkage），每个源文件都可能生成 inst_fetch 的符号。
	- 如果编译器未完全内联，会导致多个源文件都生成 inst_fetch 的外部符号，最终链接时出现 multiple definition 错误。
	- 错误表现：链接时报“multiple definition of `inst_fetch'”。

3. 去掉 inline，只保留 static
	- static 保证每个源文件有自己的 inst_fetch 副本。
	- 没有 inline，编译器不会内联，可能生成多份函数代码，但不会有链接冲突。
	- 错误表现：无链接错误，但可用 nm 工具看到每个目标文件都有 inst_fetch 的局部符号。

4. 去掉 static 和 inline
	- 变为普通外部函数声明。
	- 每个源文件都生成 inst_fetch 的外部符号，最终链接时 multiple definition 错误。
	- 错误表现：同2，链接时报“multiple definition”。

5. 证明方法
	- 编译时可直接观察报错信息。
	- 用 `nm` 工具查看目标文件/可执行文件的符号表，判断 inst_fetch 是否为局部符号（static）、外部符号（global）、或有多重定义。
	- 也可用 `objdump -t` 检查符号类型。

综上，static inline 是头文件函数的推荐写法，既避免链接冲突，又能提升性能。去掉 static 或 inline会导致多重定义或性能下降，去掉两者则必然链接失败。

## 编译与链接：dummy变量实体数目
1. 在 nemu/include/common.h 添加 `volatile static int dummy;`，重新编译NEMU。
	- 每个包含该头文件的源文件都会有一个 dummy 变量实体（局部静态变量）。
	- 例如，若有10个源文件包含 common.h，则最终生成10个 dummy 变量实体。
	- 验证方法：用 `nm` 工具查看目标文件（.o），可见每个文件有一个局部符号 dummy（类型为b或B）。

2. 再在 nemu/include/debug.h 添加 `volatile static int dummy;`，重新编译NEMU。
	- 每个包含 debug.h 的源文件也会有一个 dummy 变量实体。
	- 此时NEMU中 dummy 变量实体数目 = 包含 common.h 的源文件数 + 包含 debug.h 的源文件数。
	- 两处 dummy 互不影响，各自生成，变量作用域仅限于各自源文件。
	- 验证方法同上，nm 工具可分别看到 dummy 局部符号。

3. 修改两处 dummy 为 `volatile static int dummy = 0;`，重新编译NEMU。
	- 此时会出现 multiple definition 错误。
	- 原因：C标准规定，static 变量初始化会生成同名符号（dummy），但链接器要求同一目标文件内不能有多个同名初始化静态变量。
	- 之前未初始化时，编译器可能将未初始化静态变量优化为局部符号（b），不会冲突；初始化后变为全局符号（B），导致冲突。
	- 错误表现：链接时报“multiple definition of `dummy'”。
	- 验证方法：编译时直接观察报错信息。

综上，static变量在每个源文件各自生成实体，未初始化时不会冲突，初始化后会因符号类型变化导致链接错误。


## 了解Makefile：hello编译流程（详细源码分析）
在 am-kernels/kernels/hello/ 目录下执行 `make ARCH=$ISA-nemu`，整个编译流程如下：

### 1. Makefile引用链与变量流
- hello/Makefile：定义 NAME=hello，SRCS=hello.c，包含 $(AM_HOME)/Makefile。
- $(AM_HOME)/Makefile（即 abstract-machine/Makefile）：负责全局编译规则、变量定义、依赖管理。
- 通过 ARCH 变量，自动选择 arch-specific 配置（如 scripts/riscv32-nemu.mk），进一步包含 isa/platform相关mk文件，决定 ISA、平台、编译器、链接脚本、特定源文件（AM_SRCS）。
- 变量流：NAME、SRCS、ARCH、ISA、PLATFORM、LIBS、INC_PATH、CFLAGS、LDFLAGS、DST_DIR、IMAGE、ARCHIVE 等。

### 2. 检查与环境配置
- 检查 AM_HOME 是否有效，ARCH 是否在支持列表，SRCS 是否定义。
- 解析 ARCH，得到 ISA 和 PLATFORM。
- 创建 build/$ARCH 目录，所有目标文件、依赖文件、最终 elf 都放在此目录。

### 3. 依赖递归与库编译
- LIBS 默认包含 am、klib，支持自定义扩展。
- 通过 LIB_TEMPLATE 宏，递归调用 $(AM_HOME)/am、klib 等子项目的 Makefile，先编译库（archive），再编译主程序。
- 每个库都生成 build/$ARCH/*.a，主程序链接时自动包含。

### 4. 源文件与头文件组织
- SRCS 变量决定主程序源文件（如 hello.c），AM_SRCS 由 arch-specific mk 文件扩展（如 riscv/nemu/start.S 等）。
- INC_PATH 自动收集所有相关头文件目录（主项目/include、am/include、klib/include等），INCFLAGS 生成编译器 -I 参数。

### 5. 编译规则与隐式规则重写
- 重写并扩展了 make 的隐式规则：
	- $(DST_DIR)/%.o: %.c 由 gcc 编译，支持跨目录。
	- $(DST_DIR)/%.o: %.S 由 gcc 预处理+汇编。
	- $(DST_DIR)/%.o: %.cc/%.cpp 由 g++ 编译。
- 自动生成依赖文件（.d），用 -include 机制确保依赖关系正确。

### 6. 链接过程与平台适配
- 所有 .o 和 .a 被一起传给 ld（或 g++，取决于平台），生成 hello-$ISA-nemu.elf。
- 链接脚本由 arch-specific mk 文件决定（如 riscv32-nemu.mk），确保目标平台兼容。
- LDFLAGS、CFLAGS、ISA_H、COMMON_CFLAGS、AM_SRCS 等均由平台配置文件覆盖或扩展。

### 7. 编译流程总结
- 编译过程包括：预处理（头文件展开）、编译（生成汇编）、汇编（生成目标文件）、链接（生成 elf）。
- 递归编译库，主程序依赖库，自动生成依赖，跨平台适配。
- 可用 `make -n` 查看所有实际执行的命令。

综上，AM项目的Makefile体系通过变量流、递归依赖、自动头文件收集、重写规则、平台适配等机制，实现了跨平台、跨项目的高效编译和链接，最终生成 hello-$ISA-nemu.elf。

---
