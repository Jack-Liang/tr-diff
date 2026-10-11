# tr-diff — 释放前传输请求跨系统对比（abapGit 增强）

在**释放传输请求之前**，把请求里的对象与目标环境（PRD/QAS）的**当前状态**做代码级对比，
结果直接展示在 **abapGit 自己的差异对比界面**里（并排/统一视图、beacon、过滤菜单全都有）。

独立项目，唯一依赖是 [abapGit](https://github.com/abapGit/abapGit)（序列化引擎 + diff 界面都借它的）。

## 组成（3 个对象，装在 dev 和目标系统各一份）

| 对象 | 角色 |
|------|------|
| `FUGR ZTRDIFF` / FM `ZTRDIFF_SERIALIZE`（RFC-enabled） | 给定对象清单（每行 `PGMID\|OBJECT\|OBJ_NAME`），用 abapGit serializer 序列化，返回 zip（abapGit 格式文件 + `_status.txt` 每对象状态）。纯读操作 |
| `ZCL_TRDIFF_PAGE` | 子类化 `zcl_abapgit_gui_page_diff_base`，把两份 zip 注入 abapGit 的 diff 页面；不碰 repo |
| `PROG ZTRDIFF`（SE38 运行） | 编排：读 E070/E071 → 本地序列化 → RFC 调目标系统同款 FM → 解包 → 打开 diff 页面 |

## 使用

1. 两个系统装好同一版本的三件套（见下）+ abapGit。
2. dev 系统 SM59 建到目标系统的 RFC 目的地（只读用户即可）。
3. SE38 运行 `ZTRDIFF`：
   - `P_TRKORR` 请求号（任务自动包含），或 `P_OBJS` 直接列对象（`FUGR ZTRDIFF, CLAS ZCL_FOO`）
   - `P_DEST` 目标系统的 RFC 目的地；`NONE` = 本机自比（冒烟用）
   - `P_LANGU` 序列化主语言，默认 E
4. F8：先打印两侧 `EV_INFO` 概要（对象数/OK 数/FM 版本），有差异时打开 abapGit diff 页面。
   左列 = 目标系统当前内容，右列 = dev 当前内容（即导入后目标系统会变成的样子）。

## 安装（abapGit）

本目录就是 abapGit 仓库（`.abapgit.xml` + `src/`）：

- **离线**：`abapgit package`（zip）→ 两边 `abapGit → Import zip`，拉进各自的包（建议 `ZTRDIFF`）
- **在线**：推到 git 后两系统 link
- 也可走传统传输：dev 装进可传输包，随正常请求发布（推荐 —— 和 abapGit 本体的 lockstep 升级同理，天然保证两系统 FM 版本一致）

## 判定语义

- 页面里 `M/M` 文件 = 目标系统会被这次导入**改掉**的内容（review 重点）
- `A/`（dev-only）= 目标系统上**没有**的新对象
- `/A`（target-only 文件，同对象其他文件 M）= 目标系统上有 dev 序列化不出来的文件，⚠ 需人工确认（可能是目标侧更新过）
- 完全一致的文件不出现在 diff 里；全部一致时提示 "No differences"
- `_status.txt` 状态：`OK / NOT_FOUND / UNSUPPORTED / SKIPPED(LIMU→序列化其 R3TR 父对象) / INVALID`
- 两侧 FM 版本（`EV_INFO` 的 `FM_VERSION`）不一致会直接暴露，防止序列化格式差异制造假 diff

## 边界（v1）

- 仅 `R3TR`；LIMU 跳过（父对象携带内容）
- `TABU`（定制表数据，E071K）只统计条数、不比内容 —— abapGit tabu 需要 repo 级键范围配置，后续可加
- abapGit 不支持的对象类型报 `UNSUPPORTED`，不会假报"目标没有"
- diff 页面的 Refresh 菜单不可用（静态快照），切并排/统一、过滤、隐藏空 diff 等都可用
- 依赖当前 abapGit 的页面类 `zcl_abapgit_gui_page_diff_base` 内部结构（append_diff/mt_diff_files），abapGit 大版本升级时需回归

## 已验证（A4H abap-cloud-developer-trial 2025 + abapGit dev）

- FM 冒烟：FUGR 序列化 7 文件、NOT_FOUND/UNSUPPORTED 状态正确
- 页面构建三场景单测：改 1 文件→1、改 2→2、增删改→3；一致文件正确跳过
- 全链路 headless E2E：本地调用 + `DESTINATION 'NONE'` + 报表解包逻辑 + 建页 → COUNT=0（同系统自比）
- 差异演示：改 FM 源码后对比快照 → 正确报 1 处 M/M 并给出行级 diff
- diff 页面视觉验证需 SAP GUI：SE38 运行 `ZTRDIFF`，`P_OBJS = FUGR ZTRDIFF`，`P_DEST = NONE`，先自比看页面能开，再连真实双环境

## tools/（可选，不属于 abapGit 交付物）

`trdiff.py` — 命令行版编排（读 E070/E071 → 双端序列化 → 三态报告/JSON/CI gate），
走 [sap-for-agents](https://github.com/Jack-Liang/sap-for-agents) 网关 REST，适合接 CI；
`--target-zip` 支持对拍离线快照。`test_trdiff.py` 是 diff 逻辑单测（`python3 tools/test_trdiff.py`）。
