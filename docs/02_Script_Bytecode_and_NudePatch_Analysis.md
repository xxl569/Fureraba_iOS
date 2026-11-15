# 《フレラバ 〜Friend to Lover〜 HD Renewal Edition》脚本字节码与透视补丁机制分析报告

> 统计基准：由 `tools/scan_scripts.py` 对 `U:\anti\projects\game` 下全部 **14 个脚本归档**（`system.arc`、`sysprg.arc`、`sysprg2.arc`、`data01000~01890.arc`）执行全量反汇编，原始全量 JSON 见 `U:\anti\temp\Fureraba_iOS\script_scan_stats.json`。

---

## 1. 全量脚本扫描总览

- **扫描归档数**：14 个
- **BCS1 (`BurikoCompiledScriptVer1.00`) 脚本数**：208 个（总指令数 `1,840,659` 条，不同 Opcode 共 `180` 种）
- **`._bp` 系统字节码模块数**：76 个（总指令数 `263,985` 条，不同 Opcode 共 `69` 种，双字节系统调用 `SYS 0x8000+` 共 `379` 种）
- **其他非字节码条目**：6 个（全部位于 `system.arc`，外层 `DSC FORMAT 1.00` 解压后为 `bw  ` 音频：`click`、`cursor`、`TITLE_HI`、`TITLE_MI`、`TITLE_RI`、`TITLE_YU`）
- **解析异常数**：**0**（全部 208 个 BCS1 脚本 `trailing_bytes > 8` 数量为 **0**，全部 76 个 `._bp` 模块代码边界与尾部对齐填充完全闭合）

### 1.1 字符串编码分布（混合编码特征）

全量统计 BCS1 与 `._bp` 字符串字面量编码分布如下（共 `99,166` 条，0 条解码失败）：
- **ASCII**：`45,048` 条（函数名、资源名、系统标签等）
- **GBK（简体中文汉化补丁）**：`53,115` 条（集中在 `data01800~01890.arc` 剧本对白、角色名，以及 `data01200/01210` 流程图/话题选项、`sysprg.arc/keycnfgwnd._bp`、`scrslct._bp` 等汉化 UI 菜单）
- **CP932 (Shift-JIS)**：`1,003` 条（主要保留在 `*.BS5`/`*.bsc` 编译器源码调试路径如 `E:\BURIKOScriptSystem\FriendToLover_HD\Script\800_[scenario]共通\A_PROLOGUE01.BS5`、`system.arc/framework._bs`、以及 `sysprg.arc`/`sysprg2.arc` 报错提示信息中）

> **移植关键结论**：Godot 端脚本解析器绝不能假定全文件单一编码（甚至同一个 `._bp` 或脚本归档内都可能同时混用 GBK 汉化菜单与 CP932 引擎报错）；必须按字符串特征区分或离线统一转码为 UTF-8。

---

## 2. BCS1 (`BurikoCompiledScriptVer1.00`) 协议与全量 Opcode 频次

### 2.1 二进制头部格式
1. `0x00..0x1C` (28B)：固定魔数 `BurikoCompiledScriptVer1.00\x00`
2. `0x1C..0x20` (u32)：`hdr_size`（`code_start = 28 + hdr_size`）
3. `0x20..0x24` (u32)：`import_count`，紧随其后为 `import_count` 个 NUL 结尾导入模块名（如 `framework._bs` 被 205 个脚本导入、`function` 被 195 个脚本导入、`selectEX` 被 32 个脚本导入）
4. 导入表之后 (u32)：`export_count`，紧随其后为 `export_count` 组 `(NUL 结尾导出函数名, u32 相对 code_start 偏移)`

### 2.2 操作数长度表关键修正 (`0x3F SCOPE_MARK`)
实测 `data01300.arc/setup` 等脚本时发现，Opcode **`0x3F` 携带 2 个 32 位操作数 (`SCOPE_MARK <kind, arg>`)** 而非 0 个操作数：
- `a_prologue01` 中 `0x3F` 后恒紧跟成对的 `(1, ...)` 与 `(2, ...)`（各出现 `1,421` 次，1:1 配对）；
- `setup` 中存在 `0x3F (3, 0x188)`，若误将 `0x3F` 当作 0 参数指令，会把 `(0x03, 0x188)` 误判为 `PUSH_STR` 导致代码终点错位 `-336` 字节。修正 `BCS1_OP_ARGS[0x3F] = 2` 后，全库 208 个脚本 100% 对齐闭合。

### 2.3 Top 30 高频 BCS1 Opcode 频次表

| Opcode | 助记符 | 频次 | 说明 |
|---|---|---:|---|
| `0x000` | `PUSH_INT` | 879,316 | 压入 32 位整数立即数 |
| `0x003` | `PUSH_STR` | 467,587 | 压入 `code_start + arg` 字符串偏移 |
| `0x03f` | `SCOPE_MARK` | 254,378 | 双操作数作用域/调用帧标记 |
| `0x021` | `SUB` | 73,955 | 整数减法 |
| `0x01c` | `CALL_EXTERNAL` | 61,903 | 调用外部/框架导出函数 |
| `0x140` | `SYS_TEXT_PRINT` | 51,849 | 文本/对话输出系统调用 |
| `0x001` | `PUSH_ADDR_REL` | 11,639 | 压入代码/跳转目标偏移 |
| `0x018` | `JMP` | 5,879 | 无条件跳转至栈顶目标偏移 |
| `0x019` | `JCC` | 5,403 | 条件跳转（1 word 参数：`0`=JZ 假跳 `3,438` 次，`1`=JNZ 真跳 `1,965` 次） |
| `0x002` | `PUSH_OFFSET` | 5,210 | 压入变量/帧偏移 |
| `0x07f` | `DEBUG_LINE` | 3,175 | `(源文件偏移, 行号)` 调试信息 |
| `0x030` | `CMP_EQ` | 3,163 | 相等比较 |
| `0x020` | `ADD` | 3,159 | 整数加法 |
| `0x008` | `READ_MEM` | 2,105 | 读工作变量/内存 |
| `0x0f7` | `SYS` | 1,965 | 引擎系统调用（立绘/调度控制相关） |
| `0x009` | `WRITE_MEM` | 1,883 | 写工作变量/内存 |
| `0x022` | `MUL` | 1,394 | 乘法 |
| `0x0f6` | `SYS` | 1,265 | 引擎系统调用 |
| `0x0f0` | `SYS` | 622 | 引擎系统调用 |
| `0x00a` | `POP_VAR` | 518 | 弹出并写回变量 |
| `0x0f3` | `SYS` | 510 | 引擎系统调用 |
| `0x010` | `PUSH_SP` | 483 | 压入栈帧指针（函数序言 `ADD`/尾声 `SUB` 与 `0x011` 严格 `483:483` 成对） |
| `0x011` | `POP_SP` | 483 | 弹栈更新栈帧指针 |
| `0x01b` | `RET` | 390 | 函数/脚本返回 |
| `0x038` | `BOOL_AND` | 312 | 逻辑与 |
| `0x01a` | `CALL` | 223 | 脚本内部函数调用（跳转到栈顶内部函数地址） |
| `0x0f9` | `SYS` | 205 | 引擎系统调用 |
| `0x0f4` | `SYS` | 203 | 引擎系统调用 |
| `0x13d` | `SYS` | 156 | 引擎系统调用（选择肢/分支提示相关） |
| `0x034` | `CMP_LT` | 151 | 小于比较 |

> 注：其余 150 个低频 Opcode（含 `0x01d SET_RETVAL` 及各 `0x080..0x3FF` 系统调用）完整列表均已记录于 `script_scan_stats.json`。

---

## 3. 框架导出函数与脚本高频调用清单

### 3.1 `system.arc/framework._bs` 与 `data01000.arc/function` 导出函数
- **`framework._bs` 共导出 110 个底层演出函数**：涵盖立绘控制（`_DrawBS`, `_FadeBS`, `_MoveBS`, `_ShiftBS`, `_AnimateBS`, `_ShakeBS`, `_OrderBS`, `_RecipBS`, `SetSchedulingFlagOfBSControl`, `_ExecuteScheduledControl`）、背景/场景（`_DrawBG`, `_FadeBG`, `_ScrollBG`, `_EnlargeBG`, `_RotateBG`, `_ShakeBG`, `_WaveBG`, `_DrawScene`, `_FadeScene`, `_DrawSceneByVirtualBG`）、头像与精灵（`_DrawFace`, `_FadeFace`, `_DrawSPR`, `_FadeSPR`, `_MoveSPR`, `_ShiftSPR`, `_AnimateSPR`）、音频与视频（`_PlayBGM`, `_FadeBGM`, `_StopBGM`, `_ChangeVolumeOfBGM`, `_PlaySE`, `_FadeSE`, `_StopSE`, `_PlayStreamSE`, `_FadeStreamSE`, `_StopStreamSE`, `_ChangeVolumeOfStreamSE`, `_PlayVoice`, `_StopVoice`, `_PlayMovie`）、特效与系统（`_Quake`, `_QuakeEx`, `_Flash`, `_RippleScreen`, `_WaveScreen`, `EnableParticleScreenSx`, `EnableRainfallSx`, `_EnableSnowfall`, `_Select`, `_SelectEx`, `InitializeGlobalFlag/Work` 等）。
- **`data01000.arc/function` 共导出 6 个辅助函数**：`AutoSave`、`clear_bs`、`Random`、`SetBustshotTime`、`SoundStopAll`、`testFunc`。

### 3.2 剧本实际外部调用频次 Top 20 函数（`0x01c CALL_EXTERNAL`）
`_PlayVoice` (21,161) > `_DrawBS` (15,916) > `_FadeBS` (3,697) > `_ExecuteScheduledControl` (3,570) > `_Font` (2,862) > `_DrawScene` (2,790) > `_PlaySE` (2,571) > `StartShakingOfWindowSx` (1,322) > `_Wait` (1,251) > `_FadeBGM` (1,154) > `_PlayBGM` (1,131) > `_ScrollBG` (739) > `SelectTalk` (629) > `_PlayStreamSE` (340) > `_MoveBS` (325) > `_FadeStreamSE` (324) > `_QuakeEx` (302) > `_DrawSPR` (274) > `_WaitToFinishSE` (236) > `SetBustshotTime` (225)。

---

## 4. `._bp` 字节码与 `sysprg2.arc/nudeprcs._bp` F12 透视切换机制分析

### 4.1 `._bp` 字节码协议要点
- **16 字节固定头**：`<4I>`，即 `(header_size=16, payload_size, 0, 0)`，代码+字符串载荷总长即 `payload_size`。
- **变长指令集**：
  - `0x00, 0x08, 0x09, 0x0A, 0x15, 0x19`：1 字节立即数；
  - `0x01, 0x04, 0x05, 0x06, 0x0C`：2 字节立即数（其中 **`0x05` 为 PC 相对字符串引用** `pc + s16`，**`0x06` 为 PC 相对跳转** `pc + s16`）；
  - `0x02`：4 字节立即数（全局地址/常量）；
  - `0x80..0xFF`：2 字节大端系统调用 `(b0 << 8) | b1`（全库共检出 379 个 `_bp` 系统调用，Top 频次为 `0x805f` (422), `0x9012` (219), `0x8040` (195), `0x8041` (195), `0x805c` (180), `0x801b` (116), `0x8004` (115)）。

### 4.2 `sysprg2.arc/nudeprcs._bp` 与 F12 服装透视机制（实证还原）
通过反汇编 `system.arc/ipl._bp`、`sysprg2.arc/nudeprcs._bp`、`sysprg.arc/environ._bp` 并核查 `data02100.arc` 立绘资产，透视补丁工作链路完整如下：

1. **模块挂载入口 (`system.arc/ipl._bp` 代码 `@0x0e1f..0x0e34`，字符串 `@0x1d4d/0x1d59`)**：
   - 引擎启动时，`ipl._bp` 除加载 `sysprg.arc` 下的 `environ._bp`、`bitmap._bp`、`wrkflg._bp` 等常规系统模块外，显式检测 (`SYS 0x8034`) 并从补丁归档 `sysprg2.arc` 加载 **`nudeprcs._bp`** (`SYS 0x8040`)。
   - 对照 `Backup/` 目录可知，汉化补丁并未改动 `sysprg2.arc`（当前与备份均完全一致为 6,109 字节），`nudeprcs._bp` 属于官方预约特典「服装透过补丁」核心组件。

2. **立绘双版本资产 (`Archive/data02100.arc`)**：
   - 全归档共 `2,938` 个立绘条目，其中包含 **`549` 对严格配对的 `(name, name + "h")` 立绘**，且不存在任何无基图对应的孤立 `h` 条目（0 个）。
   - 以 `hi01wa_n` 与 `hi01wa_nh`（均为 `1280x938 32bpp RGBA`）实测像素对比：`RGB diff bbox = (441, 333, 808, 938)`、`Alpha diff bbox = (441, 338, 808, 885)` —— 头部与外轮廓完全重合，差异严格局限在躯干服饰区域（`_nh` 为对应透明/内衣裸露版本）。

3. **`nudeprcs._bp` 按键监听与状态同步 (`0x06af..0x08b1`)**：
   - 在主循环检查中，`nudeprcs._bp @0x06b9` 调用 **`SYS 0xa024(buf, 0x80, 0x40)`** 读取系统按键状态缓冲区（与 `title._bp`、`syswnd._bp`、`keycnfgwnd._bp` 一致，检查按键按下标志位 `0x80000000`），触发音效提示调用 `SYS 0x804c`。
   - 状态变更后通过 `SYS 0x8040("sysprg.arc", "environ._bp")` / `SYS 0x8041` 读写环境配置全局结构体 `0x224c8 + 0x260` 标记位（并受 `SYS 0x8018`/`0x8019` 互斥锁保护）。

4. **双图层立绘加载与透视渲染分流 (`0x012f..0x026f`, `0x26b6..0x2902`)**：
   - **资产探测 (`0x012f..0x026f`)**：调用 **`SYS 0xff40("data02xxx.arc", ...)`** 依次检查基础立绘名与拼接 `'h'` 后缀的透视立绘名是否存在，分别装入对象缓冲区 `+0x465`（常规着装图层）与 `+0x466`（`_h` 透视图层）。
   - **渲染路径切换 (`0x275a..0x2902`)**：
     - 当透视模式关闭（或无 `_h` 差分）时：走 **`SYS 0x9056`** 单图层绘制流程（仅绑定 `+0x465`，透明权重 `0x100`）；
     - 当透视模式开启时：走 **`SYS 0x9058`** 双图层合成流程（同时传入 **`buf+0x465` 与 `buf+0x466`** 两个表面句柄，设置混合参数 `0x18534+0x20 = 1`），随后调用 `SYS 0x9030` 与 `SYS 0x8004` 提交合成渲染。

> **iOS 移植建议**：在 iOS 触控设备上没有物理 `F12` 键，阶段二可在快捷菜单/HUD/双指手势中提供「透视模式 (F12)」开关，并直接在 Godot 精灵节点中按 `data02100` 的 `name` + `name + "h"` 规则做双层 `TextureRect` 叠化/切换，无需强依赖 Windows 虚拟键码轮询。
