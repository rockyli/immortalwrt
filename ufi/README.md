# 高通 410 上网棒构建

本候选分支 `ufi-v25.12.2` 以官方正式标签 [ImmortalWrt v25.12.2](https://github.com/immortalwrt/immortalwrt/tree/v25.12.2)（`4fc16f2985a`）为直接基线，内核为 6.12.103。从维护分支 `66f15c9b1bd` 移入社区板级差异和两板构建、升级、验收配置。通用 feeds 按该标签的 `feeds.conf.default` 锁定，OpenStick 保留原提交。两板构建与真机验收待完成。

官方上游为 immortalwrt/immortalwrt。设备分支 ufi-msm8916 从 x7780 锁定的社区提交 `7fe583d96eabe34efdc2f764a6f413a56e687eca` 起步。该提交的第二父提交 `a0863614715f843cea107748399b46f4e46df4b1` 用于对照官方源码。初版保留社区提交的完整历史和适配，便于复查改动；它包含其他 MSM8916 板型。

| PCB | profile | 镜像状态依据 |
| --- | --- | --- |
| UFI001C_MB_V01 | openstick-ufi001c | 旧 x7780 固件在本机启动过，6.12.85 / LK1ST。新构建单独验收。 |
| UFI003C_MB_V02 | openstick-ufi003 | 商家系统的三项 ufi003 固件包、共用设备树和 p14 布局已核对。本项目镜像待真机验收。 |

## 板级改动

- `target/linux/msm89xx/` 包含设备树、6.12 内核配置、memshare 补丁、内核模块和镜像配方。两板使用 msm8916-thwc-ufi001c 设备树，各自选择匹配的 modem、WCNSS 和 Wi-Fi NV 包。引导参数指定 /dev/mmcblk0p14。
- `package/kernel/` 的社区差异涉及 netdevices、USB 及无线模块定义。基线另带 power 按键、musl 兼容头及 openstick feed。同步上游时可用下列命令复核全部差异。
- `ufi/common.config` 选择 ext4、1024 MiB 根分区、LuCI、ModemManager、QRTR、rmtfs、OpenStick 初始化和扩容。两份 PCB 配置显式指定板型及三项固件包。基带包与每台设备自己的 NV 备份应分别保存。
- 对照的 x7780/immortalwrt-Actios 版本为 `89e77bc84e0cb4a15fd11c8fb14f91aba808b814`。本仓库编译检出的源码，用精简配置与六个固定 feed 构建；feed 锁按主源码提交时间选取，历史镜像的确切 feed 清单未知。

```sh
git diff --stat a0863614715f843cea107748399b46f4e46df4b1 7fe583d96eabe34efdc2f764a6f413a56e687eca
```

## 构建与更新

向 ufi-msm8916 推送代码会分别编译两块 PCB。工作流设有两板选择输入；GitHub 网页的手动触发入口要求该工作流也存在于默认分支。构建校验配置及 boot/system 镜像的哈希，保留 manifest、完整配置、diffconfig、feeds 和源码版本。CI 对每块板单独检查三项无线固件包及升级包。

同步官方更新时，先从已验收提交建立候选分支，合入选定官方提交，审查上述板级差异，按需要成组更新 feeds。构建、启动、USB 管理、Wi-Fi、蜂窝注册和数据通信逐项记录。单臂旁路脚本作为系统启动后的配置阶段独立验收。

## 升级包和软件源

两块板的构建分别归档 Fastboot boot/system 镜像和解压后的 sysupgrade.tar。旧 x7780 及首版 351d5f293a8 没有此平台处理器，首次迁移使用已核对布局的 LK1ST Fastboot。后续版本可从带本处理器的系统运行 `sysupgrade -T /tmp/固件.tar` 做无写入检查。CI 验证制包、ext4、完整性和负例；真机升级、保留配置及重启仍需单独实测。

处理器核对安装固件标识、运行设备树、根启动参数和历史记录的 14 个 eMMC 分区的标签、起点、容量。两块板共用 DT，软件标识不等同于物理丝印检测。实测两板 p14 起点均为 659456，UFI003C 容量为 6975455 个扇区，UFI001C 为 7073759。两板升级包分别绑定 PCB。布局或包校验失败返回 74，阻止普通 sysupgrade 强制刷入。进入 RAM 后再次检查，验证 rootfs 和 boot 内容并在写后回读。内核最后写入。单槽写入期间没有原子回滚。包内摘要用于检错，下载应核对可信构建产物的 SHA256SUMS。

使用 ImmortalWrt 25.12.2 的 aarch64_generic 通用软件源，并按构建产物中的 apk-compatibility.txt 核对签名及示例依赖求解。官方没有该 MSM8916 target 的内核包仓库。更新里程碑时逐项核对用户态库 ABI。带 kmod 依赖的包需配套同次 CI 的模块；当前制品不发布完整私有 APK 仓库。

## 两块板的出厂网络配置

LAN 管理地址为 `192.168.4.1/24`。上网棒为 USB 和 Wi-Fi 接入的客户端分配 DHCP 地址，沿用 dnsmasq 的起点 100、数量 150，即 `192.168.4.100` 至 `192.168.4.249`。XR30 的 USB 上联网口可从该地址池取址，XR30 自己的 LAN 继续使用 `192.168.10.0/24`。

默认 2.4 GHz 热点 `ImmortalWrt` 使用 WPA2-PSK，出厂密码为 `1234567890`。上述默认值在生成新配置时应用。保留配置升级的设备继续使用恢复的网络、DHCP 和无线设置。

## PSG 安装前提与真机验收

每个板型的构建分别检查最终 manifest 和 system.img 的 APK 安装数据库。四个模块包 tun、inet-diag、nft-tproxy、netlink-diag 均须依赖镜像内 kernel 包的精确 ABI。CI 使用镜像自带的 apk 刷新签名索引，对已固定 SHA-256 的 OpenClash 0.48.002 APK、PSG v2.4.5 依赖、ss、Tailscale 和其 LuCI 面板进行一次联合安装模拟。失败详情在对应板的 apk-compatibility.txt。ss 和 Tailscale 使用届时官方源的可解版本，报告记录实际求解结果。

| 板型 | 改动前的真机软件检查 | 新版 TUN / TPROXY / OpenClash 与 Mihomo / Tailscale |
| --- | --- | --- |
| UFI003C_MB_V02 | 6.12.85 官方源刷新成功。OpenClash 0.48.002、Tailscale 1.104.1-r1 缺 kmod-tun，ss 6.18.0-r2 缺 kmod-netlink-diag，PSG 还要求另两个模块。 | 待刷机实测 |
| UFI001C_MB_V01 | 尚无同项实测 | 待刷机实测 |

刷入各自镜像后分别记录板型、源码提交、内核 ABI、包版本及下列结果。完成 PSG 软件安装后用 ip-full 临时创建 TUN 设备；nft 只检查事务，不添加生效规则：

```sh
cat /usr/share/ufi/pcb
uname -r
apk list --installed --manifest | grep -E '^(kernel|kmod-(tun|inet-diag|netlink-diag|nft-tproxy)|tailscale|ss|luci-app-openclash) '
test -c /dev/net/tun && ip tuntap add dev psg-test0 mode tun && ip tuntap del dev psg-test0 mode tun
nft --check -f - <<'NFT'
table ip psg_verify_tproxy {
    chain test {
        type filter hook prerouting priority mangle; policy accept;
        meta l4proto { tcp, udp } tproxy to :7893 accept
    }
}
NFT
```

配置有效的 OpenClash 配置文件并启动服务后，记录 /etc/init.d/openclash status、实际核心进程（clash 或 mihomo）和监听端口（ss -lntup）。启动 Tailscale 后，记录 /etc/init.d/tailscale status 与 tailscale status --json 的 BackendState；分别标明服务是否启动、节点是否已授权上线。公开验收记录只保留结果，省略订阅、节点地址及认证信息。

## LuCI、OpenClash 和 HTTPS 的新版验收

两块板使用同一源码提交和 `ufi/feeds.conf` 锁定的 feeds，在构建时配套安装 ucode、libucode、ucode-mod-lua、luci-base、luci-lua-runtime、luci-compat。Tailscale、Tailscale LuCI 面板、OpenClash 和 Mihomo 均由部署阶段提供。CI 检查出厂镜像的 manifest、已装包数据库和核心文件。CI 在每块板的 system.img 副本上加载 Lua 模块，再安装 PSG v2.4.5 的依赖、面板和固定版本的 OpenClash APK，复查运行库版本、Lua 模块加载、Tailscale 版本与实际菜单路径。此处使用 OpenClash 0.48.002 作兼容性基线；后续新发布的插件和核心还需在部署时验证。该安装跳过包脚本；登录、服务状态和网络访问按下表在硬件上验收。

uHTTPd 首次启动时通过设备自身的随机源生成密钥和自签证书。首次连接请从设备本地核对证书指纹。已有监听地址和已有证书可随保留配置升级恢复。请在干净首次启动的两台设备上做证书独立性检查。

| 板型 | 此前真机结果 | 新版首次启动 | 部署 PSG v2.4.5 后 | 重启后 |
| --- | --- | --- | --- | --- |
| UFI001C_MB_V01 | 核心正常，Lua ABI 不匹配使菜单缺失。原镜像仅 HTTP；手动补装和配置后 HTTPS 可用。 | 待验 | 待验 | 待验 |
| UFI003C_MB_V02 | 本项待独立验证 | 待验 | 待验 | 待验 |

每阶段记录板型和固件提交，执行以下检查。期望 Lua 输出 `object`，回环 HTTPS 返回 2xx 或 3xx。首次启动时若尚无 curl，可在设备上用 `openssl s_client`，配合下方命令读取 HTTP 状态行。

```sh
cat /usr/share/ufi/pcb
ucode -e 'print(type(require("lua")), "\n")'
printf 'GET / HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n' |
    openssl s_client -quiet -connect 127.0.0.1:443 2>/dev/null | head -n 1
openssl x509 -inform DER -in /etc/uhttpd.crt -noout -fingerprint -sha256
openssl x509 -inform DER -in /etc/uhttpd.crt -pubkey -noout | sha256sum
```

1. 比较两板的证书指纹和公钥摘要，应分别不同；同一板重启前后应相同。保留私钥在设备本地。
2. 首次启动及重启后，从 LAN 客户端通过 `https://192.168.4.1/` 进入 LuCI 登录页。
3. 部署 PSG 并启用有效的 OpenClash 配置后，用已登录会话打开「服务 → OpenClash」，确认概览显示 Mihomo 正在运行；记录当前软件源面板提供的 Tailscale 菜单路径，并确认页面可打开。用获准的 Tailnet 客户端经设备 Tailnet 地址访问 HTTPS 登录页，重启后复测两面板及 Tailnet。
4. 每阶段核对生效的防火墙规则，确认蜂窝接口归属 WAN，WAN 入站拒绝且无管理端口放行。使用能到达该 WAN 的外部测试端验证 TCP 80/443 无法访问（同时覆盖可用的 IPv4 和 IPv6）；用 WAN 入站计数或抓包确认探测确实抵达设备。运营商 NAT 导致的不可达单独记录为外部探测未验证。
