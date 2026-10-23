# 至善园 MiniEAP LuCI 校园网认证页面

版本：1.3。为已有的 `minieap-sysu` 服务提供网页管理，适用于中山大学东校园至善园的部署方式。
这是社区适配页面，并非锐捷、学校或 GL.iNet 官方插件。

## 功能与实测范围

- **LuCI → 服务 → 校园网认证**：保存 NetID/密码，密码留空时保留原值。
- 启动、停止、重新认证，以及开机启动开关。
- 分别显示服务运行、eth0 网线连接、WAN IPv4 地址和 WAN 接口状态。
- 保存配置不自动重启服务；立即应用时再点击“重新认证”。

实测设备为 GL-MT3600BE，GL.iNet 4.9.0 / OpenWrt 21.02-SNAPSHOT，ARM64，校园网口为 `eth0`。
校园网认证已在该环境成功，用户已确认修正缓存后页面保存正常。所有页面按钮、其他固件与
其他网卡组合尚未完整实机验证。**服务运行或取得 WAN 地址不等于已成功认证或可访问互联网。**

此目录不会改写上游认证算法，也不提供预编译认证内核。LuCI 页面本身不依赖 CPU 架构，
但认证程序必须为设备架构和固件编译。需要旧版 Lua LuCI；缺少兼容组件时，从本机固件软件源
安装 `luci-compat`。GL.iNet 原厂后台可通过“系统 → 高级设置 → LuCI”进入页面。

## 与已有 MiniEAP 软件包的区别

页面管理以下固定路径，不是 netifd 的网络接口编辑器：

| 文件 | 用途 |
| --- | --- |
| `/usr/sbin/minieap-sysu` | 已部署的认证程序 |
| `/etc/minieap-sysu.conf` | 账号和认证配置 |
| `/etc/init.d/minieap-sysu` | procd 服务 |
| `/usr/libexec/minieap-sysu-run` | 等待 eth0 链路后启动认证 |

目前网卡固定为 `eth0`。其他设备请同时适配页面、配置和 runner，不能只在配置里改网卡。
如果已经使用这些路径并成功认证，直接安装页面即可。

## 安装页面

在电脑上检出本仓库后，用 Python 3 打包：

```sh
python3 openwrt/luci-app-minieap-sysu/build_bundle.py
```

输出到本目录的 `dist/minieap-sysu-luci.tar.gz`，旁边附 SHA256 文件。
Windows 上可以将 `python3` 换成可用的 `python`。上传到路由器：

```sh
scp -O openwrt/luci-app-minieap-sysu/dist/minieap-sysu-luci.tar.gz root@192.168.8.1:/tmp/
```

在路由器 SSH 中安装：

```sh
mkdir -p /tmp/minieap-luci-install
tar -xzf /tmp/minieap-sysu-luci.tar.gz -C /tmp/minieap-luci-install &&
sh /tmp/minieap-luci-install/install.sh
```

安装脚本校验包内文件，备份旧版页面，添加三个 Lua/模板文件，并清除 LuCI 临时编译缓存。
安装不会修改现有账号、重启认证、改动防火墙或 OpenClash。退出 LuCI 后重新登录。
`runtime/` 仅作为示例随包提供，不由页面安装脚本覆盖到系统。

## 尚未配置服务时

先按仓库根目录说明，为设备编译并验证 MiniEAP 可执行文件。确认网卡确实是 `eth0`，
并停止其他认证客户端。下面操作只适用于首次部署，已有可用配置时不要覆盖。

将可执行文件传至 `/tmp/minieap`，将本目录的 `runtime/` 传至 `/tmp/minieap-runtime/`。
在路由器中执行：

```sh
mkdir -p /usr/libexec
cp /tmp/minieap /usr/sbin/minieap-sysu
chmod 755 /usr/sbin/minieap-sysu
cp /tmp/minieap-runtime/minieap-sysu.init /etc/init.d/minieap-sysu
cp /tmp/minieap-runtime/minieap-sysu-run /usr/libexec/minieap-sysu-run
chmod 755 /etc/init.d/minieap-sysu /usr/libexec/minieap-sysu-run
if [ ! -e /etc/minieap-sysu.conf ]; then
    (umask 077; cp /tmp/minieap-runtime/minieap-sysu.conf.example /etc/minieap-sysu.conf)
fi
```

然后安装页面，在页面填写自己的账号密码、保存并点击启动。根据实际结果开启开机认证。
该示例使用标准 EAP、`sockraw`，没有启用 `rjv3` 扩展；这对应此次至善园成功部署，
不代表所有校区或宿舍网口都采用相同参数。

## 密码保存与故障排查

- 写入使用临时文件加原子替换，权限为 `rw-------`；旧配置保存在
  `/etc/minieap-sysu.conf.web-backup`，同样只有 root 可读写。
- 已保存密码不会返回浏览器。输入限制防止换行注入，服务动作使用固定白名单，写操作检查
  登录会话与 CSRF token。配置及备份仍是路由器上的明文文件，需保护管理员访问权限。
- `bad argument #3 to 'open'`：旧版本把 POSIX 数字权限 `384` 直接传给 nixio；
  已改用明确的 `rw-------`。如果文件已更新但错误不变，清除 LuCI 编译缓存。
- LuCI 21.02 的模块缓存文件名为完整模块名的十六进制编码；修改源码、刷新网页或只重启
  uhttpd 可能仍加载旧缓存。修复后可执行：

  ```sh
  rm -f /tmp/luci-modulecache/* /tmp/luci-indexcache /tmp/luci-indexcache.*
  /etc/init.d/uhttpd restart
  ```

- 停止认证程序不保证服务器立刻释放在线会话。如提示账号同时在线数量超限，先让原有设备
  通过认证客户端主动下线，必要时通过校园网管理渠道清理残留会话。

## 开发验证

在 Linux / WSL、Lua 5.1 和 Python 3 环境，从仓库根目录运行：

```sh
lua5.1 openwrt/luci-app-minieap-sysu/tests/test_adapter.lua openwrt/luci-app-minieap-sysu
python3 openwrt/luci-app-minieap-sysu/tests/test_cache_cleanup.py
sh -n openwrt/luci-app-minieap-sysu/install.sh
python3 openwrt/luci-app-minieap-sysu/build_bundle.py
```

测试覆盖模拟 LuCI 环境下的密码保留、特殊字符、输入校验、私有权限、原子写入失败、
POST/CSRF、模板转义、服务动作白名单，以及真实缓存文件命名方式的清理回归。
这些测试不能替代不同路由器上的实机验证。测试凭据均为虚构字符串。

## 卸载页面

```sh
rm -f /usr/lib/lua/luci/controller/minieap_sysu.lua
rm -f /usr/lib/lua/luci/model/minieap_sysu.lua
rm -f /usr/lib/lua/luci/view/minieap_sysu/index.htm
rm -f /tmp/luci-modulecache/* /tmp/luci-indexcache /tmp/luci-indexcache.*
```

上述操作只移除页面，认证程序、服务和账号配置仍保留。

## 许可证

本目录新编写的 LuCI 适配代码及辅助脚本采用 [MIT](LICENSE)；上游 MiniEAP 保持仓库根目录
的 GPL-3.0 许可证及原作者声明。感谢 undefined443/minieap-sysu、updateing/minieap 和 LuCI 项目。
