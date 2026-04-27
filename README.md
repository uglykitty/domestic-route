# domestic-route

用于在系统启动后，把国内网络路由写入当前系统路由表。

脚本会从 APNIC 下载最新地址分配数据，提取中国大陆的 IPv4/IPv6 网段，并把这些网段添加到当前默认网关和默认网卡上。脚本还会额外添加 `10.0.0.0/8`，以及 `wangguofang.net` 当前解析到的 IPv4 地址。

这些路由只写入当前系统路由表，通常在重启后需要重新运行。

## 重要

系统启动后，一定要先执行本脚本，再启动 VPN 软件。

如果先启动 VPN 软件，系统默认网关和路由表可能已经被 VPN 修改，脚本添加的国内路由可能会指向错误的网关或网卡。

## Windows 使用方法

系统启动后，在资源管理器中找到：

```text
domestic-route.bat
```

右键该文件，选择“以管理员身份运行”。

`domestic-route.bat` 会自动以管理员权限启动 `domestic-route.ps1`。如果系统弹出 UAC 权限确认窗口，请选择允许。

也可以在已管理员运行的 PowerShell 中执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\domestic-route.ps1
```

## Linux 使用方法

Linux 上需要以 root 身份运行，推荐使用 `sudo`：

```bash
sudo ./domestic-route.sh
```

如果脚本没有执行权限，先执行：

```bash
chmod +x domestic-route.sh
sudo ./domestic-route.sh
```

## 依赖

Linux 需要系统中可用以下命令：

- `curl`
- `ip`
- `awk`
- `grep`
- `dig`

Windows 需要系统中可用 PowerShell、`route.exe`，并且可以访问 APNIC 下载地址。
