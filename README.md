# PowerShell 7 路由：把 Windows PowerShell 5.1 的调用改道到 pwsh

让**你自己的** `.ps1` 在 PowerShell 7 下运行，而其余一切保持原样。默认分支永远是真正的
Windows PowerShell 5.1 —— 这是**白名单路由器**，不是系统替换。

English version: see [below](#english).

---

## 它解决什么

Windows 11 里 5.1（`powershell.exe`）和 7（`pwsh.exe`）是**两个独立产品**，5.1 无法卸载、也无法
被替换。而 5.1 有几个会静默咬人的属性：

| 事实 | 后果 |
|---|---|
| 无 BOM 的 UTF-8 脚本被按 **GBK** 读 | 含中文的脚本里，字符串会变成乱码，甚至**解析阶段就报错**（报错行号还指向别处） |
| `>` 与 `Out-File` 默认写 **UTF-16LE** | 日志对任何 UTF-8 工具都是 `a\0b\0`，`findstr`／`grep`／正则全都找不到东西 |
| 给**原生命令**传参时吃掉内嵌双引号 | 参数从第一个 `"` 处**静默截断**：`& $bash -lc "echo `"ab`"; echo END"` 只到 `ab` 为止，且不报错 |

于是"把我们的脚本固定跑在 7 上"这件事，需要一个**不依赖作者配合**的机制。

## 四层结构

前两层在**环境侧（不修改任何脚本）**，后两层在**脚本侧**：

| 层 | 位置 | 覆盖谁 | 机制 | 缺口 |
|---|---|---|---|---|
| ① 名字垫片 | `%USERPROFILE%\bin`（PATH 最前） | 从 Git Bash 进程树发起、按名字解析 `powershell` 的调用 | `powershell`（bash 精确名命中）与 `powershell.cmd`（cmd／`Start-Process` 按 PATHEXT 命中）：有 `MSYSTEM` → pwsh，否则 5.1 | Git Bash 之外无效 |
| ② **5.1 profile 路由器** | `$PROFILE`（5.1 的 profile 文件） | **任何** 5.1 启动（cmd／计划任务／别的程序／双击），**脚本无需任何改动**，含写死 `System32` 全路径 | 读 `-File` 目标，路径在根目录下 → 交给 pwsh 并结束本进程 | 带 `-NoProfile` 的调用；别的账户（SYSTEM）的 profile |
| ③ 自路由片段 | 脚本头部 | 补 ② 的 `-NoProfile` 缺口 | 5.1 启动时带原参数把自己重启进 pwsh | 属"甲方侧"：改的是脚本，对新写的／外来的脚本无效 |
| ④ `#requires -PSEdition Core` | 脚本头部 | 想"失败得响"而不是"自动改道"的脚本 | 引擎不对直接拒绝执行（exit=1） | 同上，且与 ③ 互斥 |

## 部署步骤

### 主机

```powershell
# 1) 名字垫片：把 host\ 下的四个文件放进一个位于 PATH 前的目录（默认 %USERPROFILE%\bin）
#    Git Bash 里 $HOME/bin 本来就排在 PATH 最前（Git 自带的 etc/profile.d/env.sh 负责）
Copy-Item .\host\powershell,.\host\powershell5,.\host\powershell.cmd,.\host\powershell5.cmd $env:USERPROFILE\bin -Force

# 2) 5.1 的 profile 路由器：把 host\profile-router.ps1 的内容追加进 5.1 的 profile，
#    并把里面的 $__r7Roots 改成你自己的目录（可多行）。profile 不存在就新建。
#      %USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
#    注意：整块保持纯 ASCII；不要放进 try/catch 里的那种 exit（见下面"反直觉的事实"）

# 3)（可选）给脚本加自路由片段，补 -NoProfile 缺口。默认干跑，-Apply 才落盘，幂等。
.\host\Add-Ps7SelfRoute.ps1 -Path <你的脚本目录>            # 干跑
.\host\Add-Ps7SelfRoute.ps1 -Path <你的脚本目录> -Apply    # 落盘（非 ASCII 脚本自动补 UTF-8 BOM）
```

### guest（虚拟机／另一台机器）

guest 上通常只有商店版 PowerShell 7（应用执行别名），所以垫片的第二个候选路径就是为它准备的：

```powershell
# 1) 把 guest\shims\ 下三个文件放进 guest 的 %USERPROFILE%\bin\
# 2) 装完自验（会跑一遍 guest 的 Git Bash，报出 powershell 解析到谁）
.\guest\Setup-GuestPsshim.ps1
.\guest\Test-GuestPsshim.ps1
```

**AI／远程驱动 guest 的命令**建议直接包一层 pwsh，而不是依赖名字解析（WinRM 是在 5.1 的
runspace 里执行命令，名字垫片帮不上忙）：

```powershell
# 内层 base64 是 UTF-16LE，5.1 与 7 的 -EncodedCommand 都认；
# 末尾那句是必须的：少了它，包装进程会返回 pwsh 自己的 0，失败会被读成成功。
& pwsh -NoProfile -ExecutionPolicy Bypass -EncodedCommand <utf16le-base64>
# 内层脚本末尾补： if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
```

### 验收

`host\Test-SelfRoute.ps1` 是个探针：报告自己落在哪个引擎、收到了什么参数、并返回指定退出码。

```powershell
powershell5 -File .\Test-SelfRoute.ps1 -Tag t -ExitCode 7   # 5.1 入口，期望 engine=Core、exit=7
```

## 编写 .ps1 时请带上片段

**约定：自己写、或让 AI 写 `.ps1` 时，默认让它带自路由片段** —— 不要指望调用方会把引擎挑对。
写完一条命令即可（默认干跑，`-Apply` 落盘，幂等）：

```powershell
.\host\Add-Ps7SelfRoute.ps1 -Path <脚本所在目录> -Apply
```

两条硬性要求由工具处理，手写片段时要注意：**片段必须纯 ASCII**；**含非 ASCII 的脚本要有 UTF-8 BOM**
（否则 5.1 会把无 BOM 的 UTF-8 按 GBK 读，可能在片段执行之前就解析失败）。

三个例外：会被 `dot-source` 的脚本不要加（片段把执行变成独立进程，破坏变量共享）；要"失败得响"的
脚本改用 `#requires -PSEdition Core`（与片段互斥）；调用方用 `-Command "& 'x.ps1' args"` 这种
**代码串**方式启动时，片段会**主动放过**（重建不出原参数，而丢参数改道比不改道更糟）。

## 实现成果（实测，2026-09-25/26）

机器：Windows 11 25H2（26200），Windows PowerShell 5.1.26100.9444，PowerShell 7.6.6。

| 入口（探针脚本**未做任何修改**） | 结果 |
|---|---|
| bash `powershell5 -File`（5.1 入口） | 单次执行、`engine=Core 7.6.6`、参数与 `exit=7` 透传 |
| **写死** `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -File` | `engine=Core`、`exit=6` |
| 干净 Windows PATH + 无 `MSYSTEM` 的 cmd 入口（≈ 别人的计划任务／双击） | `engine=Core` |
| 直接 `pwsh -File` | `engine=Core`（无二次启动） |
| bash 裸名 `powershell -File`（名字垫片那条路） | `engine=Core` |
| guest：用 guest 的 5.1 全路径启动 | `engine=Core 7.6.6`（走商店版别名） |
| 带 `-NoProfile` 的 5.1 入口 | `Desktop 5.1`（已知缺口，单次执行） |
| 工作区**之外**的脚本 | `Desktop 5.1`（白名单生效） |
| 交互式 5.1 会话 | `Desktop`，exit=0，不受影响 |
| 解析扫描：5.1 扫 51 个 / 7 扫 60 个脚本 | 均 0 失败（5.1 那遍是"片段可达"的前提） |

## 局限（明确边界）

- **这不是系统级替换**。cmd、计划任务、Windows 自身组件只要去调 `powershell.exe`，默认拿到的
  仍然是 5.1；只有落在白名单根目录下的 `-File` 目标会被改道。这是有意为之：默认分支必须安全。
- 带 **`-NoProfile`** 的调用不加载 profile，因此绕过 ②（由 ③ 兜底，但那要求脚本配合）。
- **别的账户**（例如 SYSTEM 的计划任务）读的是那个账户的 profile，不在覆盖范围内。
- **`-Command` 形式**没有文件可判定，一律走默认分支（保守）。
- 关联菜单的「用 PowerShell 运行」通常用 `-Command "& '%1'"` 而不是 `-File`，因此不被 ② 覆盖。
- `powershell.exe` 这个**带扩展名的拼写**在 PATH 上不再被拦截（PATH 层的解决方案见下），
  在某些 shell 里会落到 `System32` 的 5.1。
- 自路由片段会在 5.1 启动的那一次多付一次进程启动；正路启动（已是 7）只多一行判断。

## 反直觉的工程事实（都实测踩过）

1. **profile 里的 `exit` 不终止会话**。它只结束 profile，5.1 随后把调用方要跑的脚本**又执行了
   一遍**（症状：同一脚本先 Core 后 Desktop 跑两次）。必须用 `[Environment]::Exit($code)`；
   它立即终止，没有 `finally`、没有清理。因此"决定"放 `try/catch` 里，"启动 + 退出"放外面。
2. **需要被 5.1 解析的代码必须纯 ASCII**。无 BOM 的 UTF-8 文件会被 5.1 按 GBK 读，中文注释的
   误码会让 tokenizer 在目标代码**之前**就报错 —— 症状是 `意外的标记"}"` 或
   `意外属性"CmdletBinding"`，很难联想到编码。
3. **含非 ASCII 的脚本要补 UTF-8 BOM**（工具会自动补）。BOM 让 5.1 按 UTF-8 读、能解析；7 照读不误。
4. **别在块注释里写字面量 `<#...#>`**：`#>` 会提前闭合注释，报错却是"意外属性 CmdletBinding"。
5. **`-File` 调用不做逗号拆分**：`-Exclude a,b,c` 会作为一整串进来（只有 `-Command` 才拆），
   数组参数要自己 `-split ','`。
6. **给原生命令传参时 5.1 丢内嵌双引号**（见上文表格）；7 不会。
7. 写日志一律 `Out-File -Encoding utf8 -Width 4096`：缺 `-Width` 会在无控制台时按 80 列折行，
   把长 URL／token 拆成两行。

## 相关工作与先例

- [PowerShell/PowerShell #1192 — PowerShell Common Launcher for Windows](https://github.com/PowerShell/PowerShell/issues/1192)：
  官方曾设想一个通用启动器（`-version` 参数 + 配置文件定默认），最终 **Won't Fix**。
- [PowerShell/PowerShell #20789 — Enable replacing powershell.exe and 5.1 SMA.dll](https://github.com/PowerShell/PowerShell/discussions/20789)：
  官方说明为什么**不可能**完整替换：写死全路径的调用绕不过去，进程内宿主 `SMA.dll` 的应用换不了。
- [PowerShell/PowerShell #24371](https://github.com/PowerShell/PowerShell/issues/24371)：profile 里检测到
  5.1 就启动 pwsh —— 本项目的 ② 是它的**路径白名单版**（只改道指定目录下的脚本，其余不动），
  并补齐了 `exit` 不管用、必须 `[Environment]::Exit` 这个实测细节。
- [jazzdelightsme/powershellstub](https://github.com/jazzdelightsme/powershellstub)：极小转发桩（改目标即可复用其模式）。
- [ProjectSynchro/powershell-wrapper-for-wine](https://github.com/ProjectSynchro/powershell-wrapper-for-wine)：
  最完整的"替代 `powershell.exe`"实现，但面向 Wine，且已归档。
- 调用方侧先例：[gemini-cli PR #25900](https://github.com/google-gemini/gemini-cli) 改成优先 `pwsh.exe`
  再退回 `powershell.exe`，动机正是 5.1 的参数引号问题。

**没有找到的**：把这四层组合起来、**以"不修改任何脚本"为前提**、并把上面那些反直觉细节写清楚的完整方案。

## 被否决的方案（以及原因）

- **替换／符号链接 `System32\WindowsPowerShell\v1.0\powershell.exe`**：受 WRP/sfc 保护，会被还原；
  且会让依赖 5.1 的组件（尤其进程内宿主 `SMA.dll` 的）受伤。
- **IFEO `Debugger` 重定向**：唯一能抓到"写死全路径"的*名字层*机制，但要管理员、属 MITRE
  **T1546.012**（IFEO 注入）这类劫持手法，把我们的代码放进每一次 PowerShell 启动的关键路径，
  且故障时"用 PowerShell 撤销一个作用于 PowerShell 的改动"本身就很别扭。② 已经用另一种方式
  把那类调用真正改道，所以性价比不成立。
- **PATH 上放一个编译好的 `powershell.exe` 启动器**：需要一个未签名、遮蔽系统 shell 名字的可执行
  文件，且要求"参数转发永远正确"。本项目作者尝试时，本机安全扫描器把它判为**命令注入**并拦下 ——
  对"把调用方自己的参数转交给另一个进程"这类程序，这几乎是必然的误报，但也是放弃它的理由之一。

## 许可

MIT（见 `LICENSE`）。若你偏好 GPL-3.0，只需替换该文件。

---

## English

**What it is.** A weakly-global router that makes *your own* `.ps1` files run under PowerShell 7 on
Windows while everything else keeps using Windows PowerShell 5.1. The default branch is always 5.1 —
this is a whitelist router, not a system-wide replacement. 5.1 cannot be removed, and the PowerShell
team has explained why a full replacement is impossible (see the links above).

**Why bother.** PowerShell 5.1 reads a UTF-8 script without a BOM as GBK (Chinese text turns into
mojibake, sometimes a parse error on an unrelated line), writes `>`/`Out-File` output as UTF-16LE
(unreadable to every UTF-8 tool), and silently truncates an argument at its first embedded double
quote when calling a native executable. PowerShell 7 fixes all three. The point of this design is
that none of it depends on the script author cooperating.

**Four layers.** The first two live in the environment and modify nothing:

| # | Where | Reaches | Mechanism |
|---|---|---|---|
| ① | name shims in a PATH-first directory | callers inside the Git Bash process tree that resolve the bare name `powershell` | `powershell` (bash exact-name match) and `powershell.cmd` (cmd / `Start-Process` via PATHEXT): `MSYSTEM` present → pwsh, otherwise 5.1 |
| ② | **5.1 profile router** (`$PROFILE`) | any 5.1 start that loads a profile — cmd, Task Scheduler, another program, a double-click — **without touching the script**, including hardcoded `System32` paths | read the `-File` target; if it normalises to a path under your roots, run it on pwsh and terminate this process |
| ③ | self-route fragment inside the script | the `-NoProfile` case ② cannot see | on 5.1, restart itself in pwsh with the same arguments |
| ④ | `#requires -PSEdition Core` | scripts that should fail loudly instead of being rerouted | the engine refuses to run them |

**Deployment.** (1) Copy `host\powershell*` into `%USERPROFILE%\bin`. (2) Append
`host\profile-router.ps1` to `%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
and edit `$__r7Roots` there. (3) Optionally run `host\Add-Ps7SelfRoute.ps1 -Apply` over your script
directories (dry-run by default, idempotent; it adds a UTF-8 BOM to files that contain non-ASCII).
On a guest machine: copy `guest\shims\*` into its `%USERPROFILE%\bin`, run
`guest\Setup-GuestPsshim.ps1`, then `guest\Test-GuestPsshim.ps1` to confirm. For remote or
AI-driven runs, wrap the payload in
`pwsh -NoProfile -ExecutionPolicy Bypass -EncodedCommand <utf16le-base64>` and append
`if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }` inside it — without that line the wrapper
returns its own 0 and a failed command reads as success.

**When you write a `.ps1`, ship the fragment with it.** Convention: when you author a script
yourself — or have an AI author it — put the self-route fragment in it by default, rather than
relying on the caller to pick the right engine. One command does it (dry-run by default, idempotent):

```powershell
.\host\Add-Ps7SelfRoute.ps1 -Path <your scripts> -Apply
```

The tool takes care of the two hard requirements, which matter if you write the fragment by hand:
it **must be pure ASCII**, and any script containing non-ASCII text **needs a UTF-8 BOM** — without
one, 5.1 reads the no-BOM UTF-8 file as GBK and can fail to parse it before the fragment ever runs.

Three exceptions: do not add it to scripts that get dot-sourced (the fragment turns execution into a
separate process and breaks variable sharing); use `#requires -PSEdition Core` instead when a loud
failure is what you want (the two are mutually exclusive); and when a caller reaches the script
through `-Command "& 'x.ps1' args"`, the fragment **deliberately declines to redirect** — it cannot
rebuild the caller's arguments, and dropping them would be worse than staying on 5.1.

**Verified** (Windows 11 25H2; 5.1.26100.9444; 7.6.6). A probe script that had **not been modified in
any way** was launched from a 5.1 entry point, from a hardcoded `System32` full path, and from cmd
under a clean Windows PATH: all three ended on `Core 7.6.6`, with arguments and exit codes intact and
exactly one execution each. A script outside the roots stayed on 5.1, `-NoProfile` stayed on 5.1
(known gap), an interactive 5.1 session was untouched. Parse sweeps: 51 scripts under 5.1 and 60
under 7, zero failures — the 5.1 sweep is the precondition for the fragment being reachable at all.

**Limitations.** Not a system-wide replacement: cmd, Task Scheduler and Windows' own components
still get 5.1 unless they run a `-File` script under your roots. `-NoProfile` callers bypass layer ②.
Other accounts (e.g. SYSTEM) read their own profile. `-Command` invocations carry no file to
classify, so they stay on 5.1, and the Explorer "Run with PowerShell" verb uses
`-Command "& '%1'"` rather than `-File`, so it is not covered either. The `powershell.exe` spelling
is not intercepted on PATH.

**Counter-intuitive facts, all learned by measurement.** `exit` inside a profile does **not** cancel
the command the caller asked for — the 5.1 session ran the script a second time — so
`[Environment]::Exit($code)` is what actually stops it, and the decision has to sit inside
`try/catch` while the launch and the exit sit outside. Code that 5.1 must parse has to be pure
ASCII, or GBK mis-decoding breaks tokenisation before it ever runs; scripts carrying non-ASCII need a
UTF-8 BOM. Never put a literal `<#...#>` inside a block comment — `#>` closes it early and the error
points at `[CmdletBinding()]`. `-File` calls do not split commas in array arguments. Log with
`Out-File -Encoding utf8 -Width 4096`, or the token URL gets wrapped at 80 columns.

**Prior art.** Name shims and forwarding stubs already exist (links above). The profile-redirect
trick appears as a workaround in PowerShell/PowerShell#24371; this project turns it into a
path-scoped router and documents the `[Environment]::Exit` requirement it needs. Alternatives were
considered and rejected: replacing or symlinking `System32\WindowsPowerShell\v1.0\powershell.exe`
(protected by WRP/sfc, and it breaks components that depend on 5.1), IFEO `Debugger` redirection
(needs administrator, is MITRE T1546.012, and puts your code in the path of every PowerShell start),
and shipping a compiled `powershell.exe` launcher on PATH (an unsigned executable shadowing a system
shell name; a local security scanner flagged exactly that design as command injection, which is why
it was dropped rather than worked around).

**License.** MIT — replace `LICENSE` if you prefer GPL-3.0.
