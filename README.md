# <span id="前言">使用[**Github**](https://github.com/) **Release**管理历史版本的Windows OS</span>

> <font color=red>Windows OS 位于各子仓的 **Release**</font>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、友情外链](#jobs-toc-heading-1)
- [二、痛点一览](#jobs-toc-heading-2)
- [三、Github Realease](#jobs-toc-heading-3)
- [四、实操](#jobs-toc-heading-4)
- [五、子模块的多平台地址](#jobs-toc-heading-5)
- [六、脚本入口与执行流程](#scripts)
  - [【MacOS】⬆️克隆WindowsOS子仓.command](#jobs-toc-heading-7)
  - [【MacOS】⬆️Git添加WindowsOS子模块.command](#jobs-toc-heading-8)
  - [【MacOS】⏬按需下载WindowsOS Release.command](#jobs-toc-heading-9)
- [七、用法与边界](#usage)

</details>
<!-- jobs-toc:end -->

<strong id="submodule-quick-look">当前配置与按需下载</strong>

本仓是聚合父仓，下面六个目录是真正的 [**Git 子模块**](https://git-scm.com/book/en/v2/Git-Tools-Submodules)，各自保留独立历史。各子仓 Git 源码内提供说明、许可证以及 `MacOS/`、`WindowsOS/` 两套拆分 / 合并工具；Releases 只发布对应系统的分卷镜像，通过独立下载流程选择。

工具版本：MacOS 拆分 `2026.10.28`、合并 `2026.11.13`。拆分支持文件 / 目录输入，合并检查完整卷号并按数字顺序还原；Windows 默认读取相同的 `原文件名@序号of总数`，通过 `-LegacyManifest` 保留旧清单 / gzip。两端均验证大小与 SHA-256，已有目标不覆盖。Windows 工具要求 Windows 10 + PowerShell 5.1 或更新版本，不能因为镜像仓名是 XP / 2003 / 7 / 8.1 就在旧系统上直接运行；具体入口、依赖和确认见各子仓 `MacOS/README.md` 与 `WindowsOS/README.md`。MacOS 下载入口所选附件全部下载并校验通过后，若包含总卷数大于 1 的 ISO 分卷，自动调用对应子仓的 `MacOS/merge.command/merge.command`，扫描并输出到本次 `Releases/<标签>/`；单个文件、多个独立 ISO 或 `@1of1` 不合并。

| 本地子模块与说明 | Git 远端 | 镜像与附件 |
| --- | --- | --- |
| [WindowsOS_8.1](./WindowsOS_8.1/README.md) | [JobsKits/WindowsOS_8.1](https://github.com/JobsKits/WindowsOS_8.1) | [Releases](https://github.com/JobsKits/WindowsOS_8.1/releases) |
| [WindowsOS_10](./WindowsOS_10/README.md) | [JobsKits/WindowsOS_10](https://github.com/JobsKits/WindowsOS_10) | [Releases](https://github.com/JobsKits/WindowsOS_10/releases) |
| [WindowsOS_11](./WindowsOS_11/README.md) | [JobsKits/WindowsOS_11](https://github.com/JobsKits/WindowsOS_11) | [Releases](https://github.com/JobsKits/WindowsOS_11/releases) |
| [WindowsOS_2003](./WindowsOS_2003/README.md) | [JobsKits/WindowsOS_2003](https://github.com/JobsKits/WindowsOS_2003) | [Releases](https://github.com/JobsKits/WindowsOS_2003/releases) |
| [WindowsOS_XP](./WindowsOS_XP/README.md) | [JobsKits/WindowsOS_XP](https://github.com/JobsKits/WindowsOS_XP) | [Releases](https://github.com/JobsKits/WindowsOS_XP/releases) |
| [WindowsOS_7](./WindowsOS_7/README.md) | [JobsKits/WindowsOS_7](https://github.com/JobsKits/WindowsOS_7) | [Releases](https://github.com/JobsKits/WindowsOS_7/releases) |

双击 [克隆与下载入口](./【MacOS】⬆️克隆WindowsOS子仓.command)，使用 [**fzf**](https://github.com/junegunn/fzf) 选择 Git、Release 或两者，再勾选需要的 Windows 子仓。首次使用选择 **Git + Release**，先初始化并更新子仓，再进入 Release 版本和附件选择；目标子仓已经初始化时，也可直接运行 [Release 下载入口](<./【MacOS】⏬按需下载WindowsOS Release.command>)。

每个版本根目录保留本仓 Release 下载快捷入口：`【MacOS】⏬下载当前仓库Release.command` 与 `【WindowsOS】⏬下载当前仓库Release.cmd`。`MacOS/`、`WindowsOS/` 外层另提供合并、分卷与下载三项平台前缀快捷入口，按自身位置及相对路径转发到对应功能包；实施脚本只维护一份，整仓可迁移，单独克隆任一版本仓库也能使用。各版本根目录不再放 `merge.command`、`split.command`。具体入口见各版本 README；Windows 原生下载完成后使用本仓 WindowsOS 工具手工合并。

所有菜单优先使用 fzf：单选用方向键或输入搜索，`Enter` 确认；多选用 `Enter` 勾选 / 取消、`Space` 确认、`Ctrl-D` 清空，`Esc` 取消。Release 下载入口仅剩一个真实可选项（含搜索后只剩一项）时，按一次 `Space` 即确认并进入下一步。仓库等非下载多选菜单保留 `Ctrl-A` 全选。

**仅 fzf 下载附件列表采用首行全选：先完整取得附件数据，没有附件时显示空态；只有一项时仅显示该项，多项时第一行显示“全选”。** 在全选行按 `Enter` 或 `Space`，选择本次完整附件列表并进入原有下载确认；操作行不计入附件 ID、数量或分卷。下载列表取消 `Ctrl-A` 全选。普通附件行仍用 `Enter` 勾选 / 取消，多项空选时 `Space` 先勾选当前项，再按 `Space` 确认；已有勾选时只确认已选项，无匹配且空选时继续等待。

**子层按 `←` 返回上一选择面板**，顶部和底部均显示具体返回目标：同步范围返回子仓、子仓返回模式；附件返回 Release，Release 返回子仓或主入口。参数预选跳过的面板不作为返回目标；首层没有上层。选择面板不会直接启动下载，返回也不会执行待选任务。首屏自述按回车继续。克隆入口最终确认仍为直接回车执行、提示后输入任意非空内容（含空格）再回车不执行本轮，EOF 停止；Release 下载器最终确认采用下述规则。

<span id="download-confirmation-input">Release 最终下载确认</span>与附件选择分开：附件面板中的 `Space`／全选只形成计划。附件选择及计划展示期间排队的按键会在最终下载提示出现前隔离；请松开原按键，看到新提示后重新输入：直接按 `Enter`，或只输入空白（含 `Space`／`Tab`）后按 `Enter`，都会开始下载。只有包含非空白文本的回答才不执行该批下载；EOF／`Ctrl+C` 仍终止。

**附件下载位置：`<对应子仓>/Releases/<Release标签>/`**，例如 `WindowsOS_7/Releases/v1.0.0/`。Git 完成后会明确显示 Release 阶段，随后选择版本、附件并确认下载；传输时显示附件序号、百分比、速度与预计剩余时间，全部附件校验通过后，存在多卷 ISO 时自动进入对应子仓 MacOS 功能包内的合并脚本，产物留在本次下载目录。结束时分别报告新下载、已存在且校验通过、选择或确认未执行批次、本轮未检查或尝试的附件数、失败数量及合并入口状态。最终下载确认收到包含非空白文本的回答时仅说明本批未启动，不断言用户主动跳过；只有完成文件实际校验通过才计入“已存在且校验通过”，未检查／尝试不能说明已全部下载完成。

当前 `.gitmodules` 为六个子仓登记明确的 GitHub HTTPS URL 和 `main` 分支，例如：

```ini
[submodule "WindowsOS_10"]
    path = WindowsOS_10
    url = https://github.com/JobsKits/WindowsOS_10.git
    branch = main
```

| 父仓地址示例 | 当前 WindowsOS_10 的实际来源 |
| --- | --- |
| `https://github.com/JobsKits/WindowsOS.git` | `https://github.com/JobsKits/WindowsOS_10.git` |
| `https://gitee.com/JobsGo/WindowsOS.git` | `https://github.com/JobsKits/WindowsOS_10.git` |
| `ssh://git@git.example.com:2222/team/WindowsOS.git` | `https://github.com/JobsKits/WindowsOS_10.git` |

**`path` 是本地目录，`url` 是完整 Git 来源。** 父仓虽另有 [**Gitee**](https://gitee.com) remote，但这六个子仓的镜像及所需提交未核实，因此保留用户指定的 GitHub 来源。表格后两行仅说明明确 URL 不随父仓迁移，不代表已部署或实测。以后核实同站点、同 namespace 的镜像和提交可达后，才适合使用 `../真实仓名.git`；该原则同样适用于 [**GitLab**](https://gitlab.com) 和自建服务。Git 地址配置不会迁移 Release 附件。

```text
WindowsOS/
├── .gitmodules                       # 六个独立子仓的关联
├── WindowsOS_8.1/                    # 子模块；其余五个版本同级
├── WindowsOS_10/
├── WindowsOS_11/
├── WindowsOS_2003/
├── WindowsOS_XP/
├── WindowsOS_7/
│   ├── 【MacOS】⏬下载当前仓库Release.command    # 快捷入口
│   ├── 【WindowsOS】⏬下载当前仓库Release.cmd    # 快捷入口
│   ├── MacOS/
│   │   ├── 【MacOS】子卷合并.command          # 相对路径快捷入口
│   │   ├── 【MacOS】源文件压缩分卷.command    # 相对路径快捷入口
│   │   ├── 【MacOS】⏬下载Release.command     # 相对路径快捷入口
│   │   ├── merge.command/                   # 唯一合并实施脚本与说明
│   │   ├── split.command/                   # 唯一分卷实施脚本与说明
│   │   └── 【MacOS】⏬下载当前仓库Release.command/
│   ├── WindowsOS/
│   │   ├── 【WindowsOS】子卷合并.cmd         # 相对路径快捷入口
│   │   ├── 【WindowsOS】源文件压缩分卷.cmd   # 相对路径快捷入口
│   │   ├── 【WindowsOS】⏬下载Release.cmd     # 相对路径快捷入口
│   │   ├── 【WindowsOS】子卷合并/            # 功能包与说明
│   │   ├── 【WindowsOS】源文件压缩分卷/      # 功能包与说明
│   │   ├── Common/                          # Windows 工具依赖
│   │   └── 【WindowsOS】⏬下载当前仓库Release.cmd/
│   └── Releases/<Release标签>/        # 该版本附件；由子仓本地排除规则忽略
├── ReleaseDownloads/                 # 旧下载目录若存在则保留，不再写入
├── 【MacOS】⬆️Git添加WindowsOS子模块.command
├── 【MacOS】⬆️克隆WindowsOS子仓.command
├── 【MacOS】⏬按需下载WindowsOS Release.command
└── .jobs-markdown-toc/                # 本仓文档目录过滤器
```

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、友情外链 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

本目录中可独立运行的 `.command` 入口先显示内置自述：标题红色加粗，编号正文蓝色且不加粗；在终端按回车确认后才进入原有流程，按 `Ctrl+C` 取消。非彩色终端显示纯文本；没有可交互输入时停止，避免确认缺失后继续执行。

* [**一键激活 windows/office**](https://kms.cx/)
* [**Microsoft-Activation-Scripts**](https://github.com/massgravel/Microsoft-Activation-Scripts)

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、痛点一览 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

* 中国大陆的云盘产品普遍会针对非会员进行限速
* [**Github**](https://github.com/)会限制上传的**单文件大小**以及**本批次的总的文件大小**
  * 要求单文件较小（根据 [**Github**](https://github.com/) 官方文档，普通 Git 仓库中**单个对象建议不超过 1 MB**，**超过 50 MiB 会触发警告**，<font color=red>**超过 100 MiB 会被直接拒绝**</font>）
  * 且单批次推送的文件体积不宜过大（根据 [**Github**](https://github.com/) 官方文档，<font color=red>单次 push 的硬性上限为 **2 GiB**</font>）
  * 此外， [**Github**](https://github.com/) 还建议仓库整体尽量保持在 **1 GB 以内**，**小于 5 GB** 会更利于克隆、拉取和日常协作性能

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">三、[**Github**](https://github.com/) **Realease** <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

* 经常接触到的代码版本控制，实际上是针对可读性较好的文本文件进行切片式管理
* [**Github**](https://github.com/) **Realease**的设计目标是**针对代码打包以后的产物（二进制）**进行版本管理
  * 代码按照条件（平台/芯片等限制）通过编译器进行编译以后的产物，体积往往非常大

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">四、实操 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

* 环境安装/配置 [**gh**](https://cli.github.com/manual/gh)

  ```shell
  $SYSTEM_BIN_DIR/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

  ```shell
  brew install gh
  ```

* 登陆 [**gh**](https://cli.github.com/manual/gh)

  ```
  gh auth login
  ```

* 必须要存在目标仓库，且不能为0推送（否则上传至目标仓库的[**Github**](https://github.com/) **Realease**会报错）

* 上传命令

  * 如果上传的目标文件超限，则使用脚本进行拆解；将来使用时，下载后用合并脚本进行复原
  * **Windows OS**的早期版本的镜像文件并未超限，故不需要利用脚本进行拆分/合并
  * 上传文件的路径，建议用绝对路径
  * 如果希望对某个已经上传完毕的版本里面的文件进行修改，只能重新另外起一个版本进行上传（亦或者，可以删除云上错误的版本以后，再次运行下列命令，进行上传）

  ```shell
  gh release create v1.0.0 \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@1of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@2of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@3of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@4of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@1of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@2of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@3of4" \
    "~/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@4of4" \
    "~/Downloads/WindowsOS/Windows 10/split.command" \
    "~/Downloads/WindowsOS/Windows 10/merge.command" \
    -R JobsKits/WindowsOS_10 \
    -t "Windows 10 Chinese(Simplified) CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "~/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x32/Win8.1_Chinese(Simplified)_x32.iso@1of2" \
    "~/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x32/Win8.1_Chinese(Simplified)_x32.iso@2of2" \
    "~/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@1of4" \
    "~/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@2of4" \
    "~/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@3of4" \
    "~/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@4of4" \
    "~/Downloads/WindowsOS/Windows 8.1/split.command" \
    "~/Downloads/WindowsOS/Windows 8.1/merge.command" \
    -R JobsKits/WindowsOS_8.1 \
    -t "Windows 8.1 Chinese(Simplified) CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "~/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486.iso@1of2" \
    "~/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486.iso@2of2" \
    "~/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso@1of2" \
    "~/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso@2of2" \
    "~/Downloads/WindowsOS/Windows 7/split.command" \
    "~/Downloads/WindowsOS/Windows 7/merge.command" \
    -R JobsKits/WindowsOS_7 \
    -t "Windows 7 Ultimate SP1 CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 32/GZOS_XP_1.1.iso" \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 32/WindowsXP_sp3.iso" \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 32/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso" \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 32/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_x14-80404.iso" \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 64/韩文，简体中文，繁体中文版的语言包.iso" \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 64/Windows XP SP2（x64）VOL版安装序列号.txt" \
    "~/Downloads/WindowsOS/Windows XP/Windows XP 64/XP_64bit.iso" \
    -R JobsKits/WindowsOS_XP \
    -t "Windows XP CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "~/Downloads/WindowsOS/Windows 2003/Windows 2003 完整安装版.iso" \
    "~/Downloads/WindowsOS/Windows 2003/Windows Server 2003 Enterprise Edition.iso" \
    -R JobsKits/WindowsOS_2003 \
    -t "Windows 2003 " \
    -n "Split ISO upload"
  ```

  

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">五、子模块的多平台地址 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`【MacOS】⬆️Git添加WindowsOS子模块.command` 只增量补齐这六个子仓的关联，默认来源为用户指定的 `https://github.com/JobsKits/WindowsOS_*.git`。已有 section、URL、branch、gitlink 及子仓内容保留，不会删除重建子模块，也不会创建镜像。

添加分支默认 `main`，平台分支异名时通过 `SUBMODULE_BRANCH` 指定，例如：

```shell
SUBMODULE_BRANCH=gitee /bin/zsh './【MacOS】⬆️Git添加WindowsOS子模块.command'
```

克隆入口读取各层 `.gitmodules`，仅处理选中的子树。已有子仓复用自己的 remote，首次初始化使用登记来源；不会全量 `submodule sync` 改写已有子仓来源。`.gitmodules` 的显式分支严格执行，`.` 继承直接父仓分支，未配置时读取远端默认分支。只做安全快进并建立本地跟踪分支，不通过强制重置舍弃本地历史。

当前机器的六个子仓均已初始化：原有五个子仓的本地 `origin` 保留 SSH，`WindowsOS_11` 复用已有 HTTPS `origin`；共享 `.gitmodules` 使用 HTTPS，后续新克隆按共享清单取得源码。只增加另一个父仓 remote 不会切换子仓来源；Git 仓库地址兼容也不改变 Release 的实际发布平台。

Git 传输前的来源块会同时显示登记地址与实际 remote 展开地址，例如当前 WindowsOS_7 的来源字段：

```text
━━━━━━━━━━ 来源｜Git 子仓 ━━━━━━━━━━
📦 子仓：WindowsOS_7 | 🌐 平台 / 主机：github.com
登记地址：https://github.com/JobsKits/WindowsOS_7.git
拉取地址（本地规则展开）：ssh://git@github.com/JobsKits/WindowsOS_7.git
目标分支：main
```

日志还会显示父仓 remote、目标绝对路径；成功结果带来源与提交号。本地 URL 规则展开只说明计划使用的地址，联网失败会单独报错。

## 六、<span id="scripts">脚本入口与执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">[【MacOS】⬆️克隆WindowsOS子仓.command](./【MacOS】⬆️克隆WindowsOS子仓.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 按 Windows 版本选择 Git 同步、Release 附件下载或两者。

- 阅读内置自述并按回车确认，通过 fzf 单选操作模式、多选子仓；空选或 `Esc` 明确取消。
- Git 模式通过 fzf 选择向下递归或仅直属一层，只访问选中的子树。
  - 子层按 `←` 逐层返回，已确认的模式、子仓勾选和范围会在重新进入时恢复；可修改后再次确认执行。
  - 缺失或空的子仓按登记初始化，已有子仓原地复用。
  - 每层显示仓库、来源和目标分支，再获取远端最新提交并安全快进到跟踪分支。
  - 未提交源码、冲突、锁、未完成 Git 操作、本地独有提交或分叉会停止，保留现状供外部处理后重试。
  - 有效配置文档目录过滤器时调用本仓 `restore`、`verify`；未配置时明确跳过，不自动安装。
- Git + Release 先打印 Git 阶段，完成后进入同级 Release 下载入口并继续选择版本、附件；交接时保留首屏说明，省去重复的回车确认。Git 阶段失败会明确显示 Release 尚未执行。
  - Release 版本面板按 `←` 返回主入口最近实际显示的选择面板。已经完成的 Git 更新和下载保留；重新选择后仍需执行确认，不会因返回自动重跑业务。
- 即使选择 Git 递归，也不会隐式下载后代仓库的附件；只有选中的 Windows 仓库参与 Release 下载。
- 返回各阶段真实结果；未启动下载时明确说明本轮零下载，不把未检查的附件计作已完成。不暂存更新后的 gitlink、不提交、不推送。

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[【MacOS】⬆️Git添加WindowsOS子模块.command](./【MacOS】⬆️Git添加WindowsOS子模块.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 补齐六个 Windows 版本的父子 Git 关联。

- 自述确认后检查父仓、现有登记与目录，列出计划。
- 仅对缺项新增 `.gitmodules` 与 gitlink；已有登记增量保留，路径或元数据冲突停止。
- 使用 Git 原生子模块机制归集元数据，子仓根部 `.git` 为指针文件。
- 新增关联会暂存 `.gitmodules` 和对应 gitlink，这是 Git 子模块登记本身的行为；不会全部暂存父仓文件，也不自动提交或推送。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS】⏬按需下载WindowsOS Release.command](<./【MacOS】⏬按需下载WindowsOS Release.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 按仓库、Release 和附件下载需要的系统镜像。

- 使用 [**curl**](https://curl.se/) 与 [**jq**](https://jqlang.org/) 读取公开 GitHub API；无需登录。fzf 处理仓库、Release 与附件选择；依赖缺失时停止并给出安装提示，不自动安装或退回数字菜单。
- 通过 fzf 多选 Windows 子仓，逐仓单选 Release、多选附件，展示文件大小和计划总量；顶部和底部均保留操作提示。
  - 单选面板 `Enter` 确认，仅剩一项时按 `Space` 同样确认；下载附件列表取齐数据后展示，一项仅显示该项，多项首行为“全选”，在该行按 `Enter` / `Space` 选择全部真实附件并进入最终下载确认，取消 `Ctrl-A` 全选。普通多选行保留 `Enter` 勾选 / 取消、`Space` 确认；唯一真实匹配项一次 `Space` 直接确认，多项空选时先勾选当前项并等待，无匹配且空选时不推进。`Esc` / `Ctrl-C` 跳过。
  - 附件面板按 `←` 返回当前仓 Release；独立入口的 Release 面板可返回仓库多选，主入口交接时可返回主入口。直接通过 `--repo` 预选且没有前置选择面板时，Release 是本入口首层。
  - 选中 `文件.iso@1ofN`、`文件.iso@001of169` 等任意分卷时，按实际附件名称和数字卷号补齐同组全部分卷；每组只检查一次，保留原文件名，缺片、重号、总数冲突或卷号越界时停止该版下载。
  - 所选附件全部下载或既有文件校验通过后，存在总卷数大于 1 的 ISO 分卷时，调用对应子仓的 `MacOS/merge.command/merge.command --release-dir <本次下载目录>`，合并输出留在本次下载目录。单个文件、多个独立 ISO、`@1of1`、下载失败或取消时不启动合并；缺少有效的仓库合并入口会报错并保留下载文件。
- [最终下载确认](#download-confirmation-input)只读取提示后新输入；选择／计划展示期间的排队按键不会代替确认。看到提示后，空行或纯空白（含 `Space`／`Tab`）后按 `Enter` 都开始下载，仅包含非空白文本的回答不执行；EOF／`Ctrl+C` 仍终止。未启动时单独报告该批已选但尚未检查／尝试的附件数，保留已有完成文件与断点。
- 目标必须是已初始化的真实子仓；首次使用先通过主入口同步 Git。确认下载后写入 `<子仓>/Releases/<Release标签>/`，并在该子仓 `info/exclude` 追加精确的 `/Releases/` 本地排除规则，保留已有规则，不改动其受跟踪的 `.gitignore`。
- 使用清单中的官方附件直链传输，避免每下载一片都消耗匿名 API 配额；HTTPS 重定向自动跟随。
- 每个附件先显示 `[当前序号/附件总数]`；传输期间实时显示 [**curl**](https://curl.se/) 进度表中的百分比、收取字节数、速度与预计剩余时间，按行同步追加到日志。断点续传会显示已有断点大小；表中的百分比和剩余时间对应本次传输，等待服务器响应或传输量不足时可能暂时显示 `--:--:--`。
- 合并脚本由下载器传入本次 Release 目录，保留交互终端、自述与分卷组选择；无需手工寻找脚本或输入下载路径。手动运行各子仓 `MacOS/【MacOS】子卷合并.command` 快捷入口或 `MacOS/merge.command/` 内的实施脚本时，无效路径或未找到分卷会持续询问，直到输入有效目录；不想合并可关闭终端或按 `Ctrl+C`，输入结束也会停止。默认保留分卷，只有精确输入 `YES` 时才删除。合并脚本退出失败会使该仓处理返回失败；正常结束也可能是用户取消选择，以脚本自己的合并结果为准。
- API 清单明确限流时默认自动等待，无需选择菜单或重新启动。显示预计再次请求时刻与剩余分秒，每分钟更新一次；遵守 `Retry-After`／配额恢复时间，到点只重试受限的当前页，保留此前分页进度。如果仍被限流，继续按新响应等待，直到恢复或用户 `Ctrl+C`／关闭窗口结束；已完成文件与断点保留。有效服务器时间优先，无有效时间时按 60→120→240→300 秒退避，后续保持 300 秒；不提前请求，也不把过期恢复时间当作零等待循环。
- 非限流的清单错误保留恢复面板，可选择“等待恢复后重新请求”“使用本地已记录版本”或跳过本仓，`←` 返回真正上一层。权限拒绝、404 或无效 JSON 不会当作限流无限等待。
- 本地版本从真实子仓 `Releases/<标签>/.partial/*.json` 的旧附件身份记录恢复；仅展示通过路径、字段、来源与分卷完整性校验的历史计划，不虚造在线 Release ID。选定后继续选择附件并确认下载，现有完整分卷仍逐个校验后跳过；该记录不能证明当前线上是否新增、删除或替换了附件。记录缺失或失效时返回恢复面板，可等待 API 恢复后重新读取。
- 断点续传、检查大小及 API 提供的 SHA-256，校验通过才成为完成文件；“下载并校验完成”提示在彩色终端显示绿色，日志及纯文本环境不含颜色码。完整文件跳过，同名不符文件保留并报错。
- 附件超时、断流、协议错误、限流或远端拒绝访问时，持续重试当前分卷，不设次数或总时长上限；每片下载并校验通过后才继续下一片。普通网络错误按 1→2→4→…→300 秒退避，HTTP 401／403／404／429／503 从 60 秒起退避；优先遵守 `Retry-After` 和配额恢复时间，服务器要求的更长等待不会截短，零秒或过期时间回退为正数间隔。等待、传输中均可按 `Ctrl+C` 或关闭窗口取消，保留完成文件和断点。
- 传输正常结束但字节数不足时继续续传；摘要不符、字节数超出声明大小或服务器拒绝当前续传偏移时，先在 `.partial/` 保存一份问题断点，再从零重取。相同附件本轮再次出现坏候选时，只重置本轮重新获取的候选，不无限积累备份。只有校验通过才显示绿色完成提示并发布正式文件，等待恢复时不会提前启动合并。
- 持续重试不修改代理、不切换来源、不绕过证书或认证。HTTP 401／403／404 会提示可能需要处理远端权限或附件状态，同时继续等待；本地写入、配置或工具错误会明确停止并保留断点，避免反复执行无效网络请求。正式同名文件、断点身份冲突和不安全路径保持原有保护，不通过重试覆盖用户文件。
- 运行日志位于临时目录。只读清单不修改 Git 排除配置，旧 `ReleaseDownloads/` 内容保留，不自动迁移或删除。

## 七、<span id="usage">用法与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本仓根目录执行；也可双击 `.command`，脚本按自身位置定位，不依赖启动目录：

```shell
/bin/zsh './【MacOS】⬆️克隆WindowsOS子仓.command'
/bin/zsh './【MacOS】⏬按需下载WindowsOS Release.command'
```

单独下载一个版本时，在对应版本根双击分平台快捷入口，或运行以下示例；两者只查询 `WindowsOS_8.1`，不需要父仓下载器。

```shell
/bin/zsh './WindowsOS_8.1/【MacOS】⏬下载当前仓库Release.command' --list
```

```powershell
& './WindowsOS_8.1/【WindowsOS】⏬下载当前仓库Release.cmd' -List
```

MacOS 实施需 zsh、Git、curl、jq、shasum 和交互所需的 fzf；Windows 实施需 Windows 10 或更新版本、PowerShell 5.1 或更新版本、Git 和交互所需的 fzf，使用系统 .NET 请求下载，无需 MacOS 或 jq。两端均有帮助和只读清单，清单不下载附件或修改 Git 排除配置；具体按键、断点、锁、校验及失败处理见[MacOS 下载说明](<./WindowsOS_8.1/MacOS/【MacOS】⏬下载当前仓库Release.command/README.md>)与[WindowsOS 下载说明](<./WindowsOS_8.1/WindowsOS/【WindowsOS】⏬下载当前仓库Release.cmd/README.md>)，其它版本同结构。

查看父仓入口帮助、登记清单与 Release 清单，不下载大文件：

```shell
/bin/zsh './【MacOS】⬆️克隆WindowsOS子仓.command' --help
/bin/zsh './【MacOS】⬆️克隆WindowsOS子仓.command' --list
/bin/zsh './【MacOS】⬆️Git添加WindowsOS子模块.command' --dry-run
/bin/zsh './【MacOS】⏬按需下载WindowsOS Release.command' \
  --list \
  --repo WindowsOS_7
```

Git 同步需要 Git、系统 [**zsh**](https://www.zsh.org/) 与交互选择所需的 fzf，不依赖 curl、jq；遇到已启用文档目录过滤器的仓库，还需要可用的 [**Node.js**](https://nodejs.org/) 及该仓自带的还原工具，缺失时停止。Release 下载还需要 curl、jq、`shasum` 和已初始化的子仓。fzf 须支持脚本使用的顶部 / 底部提示与多选操作；缺失时可先执行 `brew install fzf`。帮助与只读清单无需 fzf，也不会弹出菜单。

Release 查询有匿名 API 速率限制，清单失败时显示 HTTP／CONNECT 状态、可用的剩余配额与恢复时间：明确限流自动等待，其它错误提供恢复面板；无附件时提示空清单。小时配额等待到服务器指定的窗口重置时刻，并非每次从报错起等满一小时；短时限流优先遵守服务器等待提示。`--list` 不自动等待或进入交互恢复面板，查询失败返回非零状态；分页未全部成功时不会把已取得的前几页当作完整清单。不会偷偷切换镜像站；来源 URL、版本、目标路径及失败对象会显示在日志中。现有网络、代理与远端配置不会被脚本改成全局设置。

| 入口 / 选项 | 当前行为 |
| --- | --- |
| 克隆入口 `--mode git\|release\|both` | 预选阶段；不指定时由 fzf 单选，`Esc` 取消。 |
| 克隆 / Release 入口 `--repo WindowsOS_7` | 预选仓库，可重复指定；不指定时 fzf 多选，`Enter` 勾选 / 取消、`Space` 确认。Release 入口仅剩一项时 `Space` 直接确认；多项空选时先勾选当前项并留在面板，再按 `Space` 确认；`Esc` 取消或跳过。 |
| 克隆入口 `--direct` | 仅直属一层；不指定时通过 fzf 选择范围，首项为向下递归。 |
| 克隆入口 `--list` | 只列本地 `.gitmodules` 登记，不联网或写入。 |
| 添加入口 `--dry-run` | 只读检查六仓关联，列出缺项，不克隆或修改索引。 |
| Release 入口 `--list` | 查询所有已发布版本及完整附件清单；未传 `--repo` 时查询六仓，不下载附件，仅写临时日志。 |
| 添加入口 `SUBMODULE_BRANCH` / `SUBMODULE_URL_PREFIX` | 新增项默认 `main` / `https://github.com/JobsKits`，不覆盖已有字段。 |
| 三个入口 `--help` | 显示帮助；普通执行均须终端交互确认。克隆入口最终确认回车执行、任意非空内容（含空格）后回车不执行；Release 下载最终确认空行或纯空白（含 Space／Tab）后回车开始，仅非空白文本不执行；EOF／Ctrl+C 终止；添加入口回车跳过、任意字符后回车执行。 |

Release 清单仍由公开 GitHub API 获取，附件使用清单中的 `browser_download_url` 官方直链传输；日志显示来源地址与目标位置。每版通过 macOS 自带 zsh 的系统文件锁限制为一个下载与合并流程，直到合并脚本结束才释放：`.download-lock` 是长期保留的普通文件，是否占用由系统判断，不能仅凭文件存在判断仍在下载，也不要在运行中删除或替换它。持有进程结束（包括强制结束）后系统自动释放占用；取得锁后还会核验同版断点是否仍有遗留传输进程或文件占用，存在则停止，不终止未知进程或重复写入。核验通过后才开始下载；正在使用的锁不会被抢占。旧版空锁目录、符号链接和含未知内容的锁文件会保留并报错，旧目录须先确认没有相关下载进程，再精确移除空目录。

续传数据位于同版 `.partial/`；远端附件身份发生变化或元数据不符时保留文件并停止，先将旧断点移到其它位置再重试。身份匹配的断点若校验不符或不能续传，自动保存至 `.partial/<附件ID>.part.rejected.XXXXXX/` 后重取，不改动已有正式文件。标签用于目录名时做 URI 编码，普通 `v1.0.0` 保持原样。

下载完成只证明与 Release 元数据一致，不等同于验证操作系统能安装、镜像来源安全或旧系统可用。全部附件校验通过后，存在多卷 ISO 时调用对应子仓的 `MacOS/merge.command/merge.command`；各版本均随仓提供相同合并脚本，不运行 Release 附件中的脚本。缺少入口或执行失败时明确报错并保留下载文件，`--list` 仍只读查询。MacOS 拆分、合并工具的 Git 源码各自以功能文件夹包装，入口与专属 `README.md` 同级；各子仓根目录不再保留 `merge.command`、`split.command`，平台外层快捷入口按相对路径转发到对应功能包，实施逻辑只保留一份。下载入口不挂载镜像或安装系统。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
