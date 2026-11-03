# 豆包环境 · 一键宝塔 + 自助建站

在 **豆包工作区**（以及任何 rootfs 易重置、无 systemd、无公网 IP 的容器）里，一条命令部署出：

- ✅ **宝塔面板**（含容器兼容补丁，安装不再卡死）
- ✅ **MySQL 8 快速安装**（官方预编译二进制，3–8 分钟，替代 1–2 小时的源码编译）
- ✅ **公网访问**（cloudflared / serveo 内网穿透，零配置、免备案、免公网 IP）
- ✅ **多端口自助建站**（20001–20030 共 30 个端口，面板里添加站点即自动暴露公网地址）
- ✅ **站点导航页**（自动生成"我的服务器站点导航"，所有站点公网地址一目了然）
- ✅ **沙箱重置自恢复**（数据落盘持久目录，重置后一条命令满血复活）

> 本项目是环境/平台层的部署方案，不含任何个人的站点源码与数据、不含任何账号密码与服务器地址。敏感信息全部参数化/占位，请放心分发。

---

## 一、一键部署

在豆包工作区（或任何 Linux 容器）里执行：

```bash
# 1. 拿到项目（GitHub 克隆 / 上传解压 / 直接发给豆包解析均可）
git clone <本仓库地址> && cd doubao-bt-deploy

# 2. 跑总入口（全程自动，日志 /tmp/bt_oneclick.log）
bash one-click.sh
```

完成后查看 `/tmp/bt_oneclick.log` 末尾的汇总：

| 项目 | 位置 |
| --- | --- |
| 宝塔面板 | `https://127.0.0.1:<面板端口>`（登录信息见面板首页/`/www/server/panel/default.pl`） |
| 面板公网地址 | `grep -E 'trycloudflare' /tmp/tunnel_panel.log` |
| 站点导航页 | 默认站点 `http://127.0.0.1:8088`（公网地址见 `/tmp/tunnel_web.log`） |

### 分步执行（不想要全自动时）

```bash
bash scripts/persist-www.sh      # 1. /www 持久化（防重置丢数据）
bash scripts/install-bt.sh       # 2. 宝塔面板（容器补丁）
bash scripts/mysql-quick.sh      # 3. MySQL 8 快装（几分钟）
PORT=8888  bash scripts/tunnel.sh panel https   # 4a. 面板公网隧道
PORT=8088  bash scripts/tunnel.sh web http     # 4b. 默认站点公网隧道
sudo nohup bash scripts/sites-monitor.sh &     # 5. 多端口建站监控 + 导航页
```

---

## 二、沙箱重置后恢复

豆包工作区重置（rootfs 还原）后，宝塔数据在持久目录里原封不动：

```bash
bash scripts/restore.sh
```

自动完成：重建 `/www` 软链接 → 启动面板/nginx/php/mysql → 重起公网隧道 → 恢复站点监控与导航页。

> 前提：部署时用过 `persist-www.sh`（one-click.sh 已内置），持久目录里有 `bt_data/www`。

---

## 三、目录结构

```
doubao-bt-deploy/
├── one-click.sh              # 总入口：一条命令全流程
├── scripts/
│   ├── persist-www.sh        # /www 软链到持久目录（幂等）
│   ├── install-bt.sh         # 宝塔安装 + 容器不兼容点补丁
│   ├── mysql-quick.sh        # MySQL 8 预编译二进制快装
│   ├── tunnel.sh             # cloudflared/serveo 内网穿透
│   ├── sites-monitor.sh      # 多端口自动隧道 + 站点导航页生成
│   └── restore.sh            # 沙箱重置一键恢复
└── docs/
    ├── 01-部署手册.md          # 从零开始的完整图文步骤
    ├── 02-弯路与避坑.md        # 踩过的坑：编译、端口、重置、隧道
    └── 03-多站点自助建站.md    # 端口段方案与导航页使用
```

---

## 四、环境要求

- Linux x86_64（Debian/Ubuntu 系最佳）
- 有 `sudo` 权限
- 能访问外网（下载宝塔安装脚本与隧道二进制）
- 无需公网 IP、无需域名备案

## 五、安全说明

- MySQL root 密码由脚本随机生成并打印在日志，**请复制到自己的密码本**
- 宝塔面板登录信息见面板首页输出，**首次登录请立即改密**
- trycloudflare 临时隧道地址每次重启会变化，正式使用可换 named tunnel（见 `docs/02-弯路与避坑.md`）
- 本项目不包含任何真实账号、密码、IP、域名或站点数据

## License

禁止商用 · 仅供娱乐 · 禁止违法用途 · 后果自行承担（详见 LICENSE 文件）
