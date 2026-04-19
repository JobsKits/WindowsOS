# 使用[**Github**](https://github.com/) **Realease**管理历史版本的Windows OS

![Jobs倾情奉献](https://picsum.photos/1500/400 "Jobs出品，必属精品")

[toc]

## 一、痛点一览

* 中国大陆的云盘产品普遍会针对非会员进行限速
* [**Github**](https://github.com/)会限制上传的**单文件大小**以及**本批次的总的文件大小**
  * 要求单文件较小（根据 [**Github**](https://github.com/) 官方文档，普通 Git 仓库中**单个对象建议不超过 1 MB**，**超过 50 MiB 会触发警告**，<font color=red>**超过 100 MiB 会被直接拒绝**</font>）
  * 且单批次推送的文件体积不宜过大（根据 [**Github**](https://github.com/) 官方文档，<font color=red>单次 push 的硬性上限为 **2 GiB**</font>）
  * 此外， [**Github**](https://github.com/) 还建议仓库整体尽量保持在 **1 GB 以内**，**小于 5 GB** 会更利于克隆、拉取和日常协作性能

## 二、[**Github**](https://github.com/) **Realease**

* 经常接触到的代码版本控制，实际上是针对可读性较好的文本文件进行切片式管理
* [**Github**](https://github.com/) **Realease**的设计目标是**针对代码打包以后的产物（二进制）**进行版本管理
  * 代码按照条件（平台/芯片等限制）通过编译器进行编译以后的产物，体积往往非常大

## 三、实操

* 环境安装/配置 [**gh**](https://cli.github.com/manual/gh)

  ```shell
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@1of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@2of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@3of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x32/Win10_22H2_Chinese_Simplified_x32.iso@4of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@1of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@2of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@3of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/Win10_22H2_Chinese_Simplified_x64/Win10_22H2_Chinese_Simplified_x64.iso@4of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/split.command" \
    "/Users/jobs/Downloads/WindowsOS/Windows 10/merge.command" \
    -R JobsKits/WindowsOS_10 \
    -t "Windows 10 Chinese(Simplified) CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x32/Win8.1_Chinese(Simplified)_x32.iso@1of2" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x32/Win8.1_Chinese(Simplified)_x32.iso@2of2" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@1of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@2of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@3of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/Win8.1_Chinese(Simplified)_x64/Win8.1_Chinese(Simplified)_x64.iso@4of4" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/split.command" \
    "/Users/jobs/Downloads/WindowsOS/Windows 8.1/merge.command" \
    -R JobsKits/WindowsOS_8.1 \
    -t "Windows 8.1 Chinese(Simplified) CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "/Users/jobs/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486.iso@1of2" \
    "/Users/jobs/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486/cn_windows_7_ultimate_with_sp1_x86_dvd_u_677486.iso@2of2" \
    "/Users/jobs/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso@1of2" \
    "/Users/jobs/Downloads/WindowsOS/Windows 7/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso@2of2" \
    "/Users/jobs/Downloads/WindowsOS/Windows 7/split.command" \
    "/Users/jobs/Downloads/WindowsOS/Windows 7/merge.command" \
    -R JobsKits/WindowsOS_7 \
    -t "Windows 7 Ultimate SP1 CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 32/GZOS_XP_1.1.iso" \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 32/WindowsXP_sp3.iso" \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 32/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso" \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 32/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_x14-80404.iso" \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 64/韩文，简体中文，繁体中文版的语言包.iso" \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 64/Windows XP SP2（x64）VOL版安装序列号.txt" \
    "/Users/jobs/Downloads/WindowsOS/Windows XP/Windows XP 64/XP_64bit.iso" \
    -R JobsKits/WindowsOS_XP \
    -t "Windows XP CN" \
    -n "Split ISO upload"
  ```

  ```shell
  gh release create v1.0.0 \
    "/Users/jobs/Downloads/WindowsOS/Windows 2003/Windows 2003 完整安装版.iso" \
    "/Users/jobs/Downloads/WindowsOS/Windows 2003/Windows Server 2003 Enterprise Edition.iso" \
    -R JobsKits/WindowsOS_2003 \
    -t "Windows 2003 " \
    -n "Split ISO upload"
  ```

  