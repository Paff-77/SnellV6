# SnellV6

在使用 systemd 的 Debian 服务器上安装或升级 Snell v6。脚本会识别 `amd64`、`i386` 或 `aarch64`，每次运行都从 [Surge 官方发布页](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) 查找该架构的最新 v6 正式包。

## 一键安装或升级

在服务器上以 `root` 身份运行以下命令。命令从公开仓库下载脚本，下载和 Bash 语法检查均成功后才执行，并在退出时删除临时文件。

```bash
(installer=$(mktemp) && trap 'rm -f -- "$installer"' EXIT && curl -fsSL 'https://raw.githubusercontent.com/Paff-77/SnellV6/main/install-snell-v6.sh' -o "$installer" && bash -n "$installer" && bash "$installer")
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

运行 `sudo cat /etc/snell/snell-server.conf` 查看 `listen` 和 `psk`。把下面的示例地址和 PSK 替换成自己的值，若端口有修改也一并替换。客户端需支持 `version=6`。[Surge 配置参考](https://manual.nssurge.com/policies/snell.html)

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
