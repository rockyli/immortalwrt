# 高通 410 上网棒构建

官方上游为 immortalwrt/immortalwrt。设备分支 ufi-msm8916 从 x7780 锁定的社区提交 `7fe583d96eabe34efdc2f764a6f413a56e687eca` 起步。该提交的第二父提交 `a0863614715f843cea107748399b46f4e46df4b1` 用于对照官方源码。初版保留社区提交的完整历史和适配，便于复查改动；它包含其他 MSM8916 板型。

| PCB | profile | 镜像状态依据 |
| --- | --- | --- |
| UFI001C_MB_V01 | openstick-ufi001c | 旧 x7780 固件在本机启动过，6.12.85 / LK1ST。新构建单独验收。 |
| UFI003C_MB_V02 | openstick-ufi003 | 候选配置。上游名称未写 C，先与商家系统的分区和基带文件对照。 |

## 板级改动

- `target/linux/msm89xx/` 包含设备树、6.12 内核配置、memshare 补丁、内核模块和镜像配方。两板使用 msm8916-thwc-ufi001c 设备树，各自选择匹配的 modem、WCNSS 和 Wi-Fi NV 包。引导参数指定 /dev/mmcblk0p14。
- `package/kernel/` 的社区差异涉及 netdevices、USB 及无线模块定义。基线另带 power 按键、musl 兼容头及 openstick feed。同步上游时可用下列命令复核全部差异。
- `ufi/common.config` 选择 ext4、1024 MiB 根分区、LuCI、ModemManager、QRTR、rmtfs、OpenStick 初始化和扩容。两份 PCB 配置显式指定板型及三项固件包。基带包与每台设备自己的 NV 备份应分别保存。
- 对照的 x7780/immortalwrt-Actios 版本为 `89e77bc84e0cb4a15fd11c8fb14f91aba808b814`。本仓库编译检出的源码，用精简配置与六个固定 feed 构建；feed 锁按主源码提交时间选取，历史镜像的确切 feed 清单未知。

```sh
git diff --stat a0863614715f843cea107748399b46f4e46df4b1 7fe583d96eabe34efdc2f764a6f413a56e687eca
```

## 构建与更新

向 ufi-msm8916 推送代码会编译 UFI001C_MB_V01。工作流设有两板选择输入；GitHub 网页的手动触发入口要求该工作流也存在于默认分支。构建校验配置及 boot/system 镜像的哈希，保留 manifest、完整配置、diffconfig、feeds 和源码版本。UFI003C_MB_V02 的配置可在核对商家布局后测试。

同步官方更新时，先从已验收提交建立候选分支，合入选定官方提交，审查上述板级差异，按需要成组更新 feeds。构建、启动、USB 管理、Wi-Fi、蜂窝注册和数据通信逐项记录。单臂旁路脚本作为系统启动后的配置阶段独立验收。

## 升级包和软件源

UFI001C_MB_V01 构建同时归档 Fastboot boot/system 镜像和解压后的 sysupgrade.tar。旧 x7780 及首版 351d5f293a8 没有此平台处理器，首次迁移使用已核对布局的 LK1ST Fastboot。后续版本可从带本处理器的系统运行 `sysupgrade -T /tmp/固件.tar` 做无写入检查。CI 验证制包、ext4、完整性和负例；真机升级、保留配置及重启仍需单独实测。

处理器核对安装固件标识、运行设备树、根启动参数和历史记录的 14 个 eMMC 分区的标签、起点、容量。两块板共用 DT，软件标识不等同于物理丝印检测。UFI003C 的商家布局未确认，当前只为 UFI001C 启用此升级格式。布局或包校验失败返回 74，阻止普通 sysupgrade 强制刷入。进入 RAM 后再次检查，验证 rootfs 和 boot 内容并在写后回读。内核最后写入。单槽写入期间没有原子回滚。包内摘要用于检错，下载应核对可信构建产物的 SHA256SUMS。

保留可访问的 ImmortalWrt aarch64_generic 通用快照索引，并按构建产物中的 apk-compatibility.txt 核对签名及示例依赖求解。官方没有该 MSM8916 target 的内核包仓库。滚动用户态库 ABI 也可能变化。带 kmod 依赖的包需配套同次 CI 的模块；当前制品不发布完整私有 APK 仓库。
