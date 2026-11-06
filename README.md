# SnellV6

在使用 systemd 的 Debian 服务器上安装或升级 Snell v6。脚本会识别 `amd64`、`i386` 或 `aarch64`，每次运行都从 [Surge 官方发布页](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) 查找该架构的最新 v6 正式包。

## 一键安装或升级

在服务器上以 `root` 身份运行以下命令。链接指向一个固定的安装脚本提交，避免取到缓存里的旧脚本。脚本仍会在每次运行时查找最新的 Snell v6 正式包。下载和 Bash 语法检查均成功后才执行，并在退出时删除临时文件。

```bash
(installer=$(mktemp) && trap 'rm -f -- "$installer"' EXIT && curl --disable -fsSL 'https://raw.githubusercontent.com/Paff-77/SnellV6/50ff7726db8d7ab7e59fca4d83415f44abb25a82/install-snell-v6.sh' -o "$installer" && bash -n "$installer" && bash "$installer")
```

普通用户把末尾的 `bash "$installer"` 改为 `sudo bash "$installer"`。如果服务器缺少 `curl`，先运行 `apt-get install -y curl`。

- 首次安装默认监听 `31777/tcp`，同时绑定 IPv4 和 IPv6，并生成随机 PSK。要自定义首次安装端口，在命令最后的 `"$installer"` 后加端口号，例如 `32777`。
- 升级时重新执行同一条命令。脚本沿用已有配置，包括端口和 PSK。升级后的服务启动检查失败时，脚本会尝试恢复旧二进制。
- 如果脚本已下载到服务器，可直接运行 `sudo bash install-snell-v6.sh`，或在首次安装时指定端口 `sudo bash install-snell-v6.sh 32777`。以 `root` 登录时直接用 `bash`。

## 检查服务与防火墙

```bash
systemctl status snell --no-pager
sudo ss -ltnp 'sport = :31777'
sudo journalctl -u snell -n 50 --no-pager
```

如果启用了主机防火墙或云安全组，放行实际使用的 TCP 端口。使用 UFW 时，默认端口的放行命令为 `sudo ufw allow 31777/tcp`。

## Surge 客户端

安装或升级成功后，脚本会打印一行可粘贴到 Surge `[Proxy]` 段的节点配置。端口取自第一条监听地址，PSK 和模式取自服务端配置文件。地址默认使用当前 SSH 会话连接到的服务器地址。如果经过 NAT、使用域名或显示 `YOUR_SERVER_IP`，请替换成客户端实际可连接的地址，也可在执行安装命令前设置 `export SNELL_SERVER_HOST=server.example.com`。[Surge 配置参考](https://manual.nssurge.com/policies/snell.html)

```ini
[Proxy]
SnellV6 = snell, server.example.com, 31777, psk=YOUR_PSK, version=6
```

## 安装路径

| 用途 | 路径 |
| --- | --- |
| 服务端程序 | `/usr/local/bin/snell-server` |
| 服务端配置 | `/etc/snell/snell-server.conf` |
| systemd 单元 | `/etc/systemd/system/snell.service` |
| 服务工作目录 | `/var/lib/snell` |
