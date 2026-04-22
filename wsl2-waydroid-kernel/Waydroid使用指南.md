# Waydroid 使用指南

本文档介绍如何在 WSL2 中配置、使用 Waydroid，包括安装 APK 和正确关闭 Waydroid 的方法。

---

## 目录

1. [启动前准备](#启动前准备)
2. [启动 Waydroid](#启动-waydroid)
3. [安装 APK](#安装-apk)
4. [关闭 Waydroid](#关闭-waydroid)
5. [常见问题](#常见问题)

---

## 启动前准备

### 1. 检查内核模块

每次 WSL2 重启后，需要确保必要的内核模块已加载：

```bash
# 加载网桥模块
sudo modprobe bridge

# 加载 iptables 相关模块
sudo modprobe ip_tables
sudo modprobe iptable_filter
sudo modprobe iptable_nat
sudo modprobe iptable_mangle
sudo modprobe nf_nat

# 加载网络地址转换模块
sudo modprobe xt_MASQUERADE
sudo modprobe xt_CHECKSUM
sudo modprobe nf_conntrack
```

### 2. 创建 waydroid0 网桥

```bash
# 创建网桥
sudo ip link add name waydroid0 type bridge
sudo ip link set waydroid0 up
```

### 3. 启动 Waydroid 网络

```bash
sudo /usr/lib/waydroid/data/scripts/waydroid-net.sh start
```

### 4. 检查 binder 设备

```bash
ls -la /dev/binder /dev/hwbinder /dev/vndbinder
```

如果设备不存在，需要重新挂载 binderfs：

```bash
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs
sudo ln -sf /dev/binderfs/binder /dev/binder
sudo ln -sf /dev/binderfs/hwbinder /dev/hwbinder
sudo ln -sf /dev/binderfs/vndbinder /dev/vndbinder
```

---

## 启动 Waydroid

### 方法 1：启动会话 + 图形界面

```bash
# 终端 1：启动 Waydroid 会话
waydroid session start

# 终端 2：启动图形界面
waydroid show-full-ui
```

### 方法 2：后台启动

```bash
# 后台启动会话
waydroid session start &

# 等待几秒后启动图形界面
sleep 5
waydroid show-full-ui
```

### 检查状态

```bash
waydroid status
```

预期输出：
```
Session:        RUNNING
Container:      RUNNING
Vendor type:    MAINLINE
```

---

## 安装 APK

### 方法 1：使用 waydroid app install

```bash
# 安装 APK
waydroid app install /path/to/your/app.apk

# 示例
waydroid app install ~/Downloads/app.apk
```

### 方法 2：使用 adb

```bash
# 安装 adb
sudo apt-get install android-tools-adb

# 连接 Waydroid 的 adb
adb connect localhost:5555

# 安装 APK
adb install /path/to/your/app.apk
```

### 方法 3：直接复制到 Waydroid 目录

```bash
# 复制 APK 到 Waydroid 用户目录
sudo cp /path/to/your/app.apk /var/lib/waydroid/rootfs/home/user/

# 进入 Waydroid shell 安装
waydroid shell

# 在 Waydroid shell 中
pm install /home/user/app.apk
```

### 查看已安装应用

```bash
waydroid app list
```

### 启动应用

```bash
# 通过包名启动
waydroid app launch com.example.app

# 或者使用应用名称
waydroid app launch "应用名称"
```

---

## 关闭 Waydroid

### 正确关闭步骤

**注意：直接关闭窗口只会隐藏界面，Waydroid 仍在后台运行！**

#### 方法 1：完整关闭（推荐）

```bash
# 1. 停止图形界面会话
waydroid session stop

# 2. 停止 Waydroid 容器服务
sudo systemctl stop waydroid-container

# 3. 停止网络
sudo /usr/lib/waydroid/data/scripts/waydroid-net.sh stop

# 4. 删除网桥（可选）
sudo ip link delete waydroid0
```

#### 方法 2：一键关闭脚本

创建关闭脚本 `stop-waydroid.sh`：

```bash
#!/bin/bash

echo "正在停止 Waydroid..."

# 停止会话
waydroid session stop 2>/dev/null

# 停止容器
sudo systemctl stop waydroid-container 2>/dev/null

# 停止网络
sudo /usr/lib/waydroid/data/scripts/waydroid-net.sh stop 2>/dev/null

# 删除网桥
sudo ip link delete waydroid0 2>/dev/null

echo "Waydroid 已停止"
```

使用方法：

```bash
chmod +x stop-waydroid.sh
./stop-waydroid.sh
```

#### 方法 3：强制停止（如果卡死）

```bash
# 强制停止所有 Waydroid 进程
sudo killall -9 waydroid
sudo killall -9 waydroid-container

# 停止 LXC 容器
sudo lxc-stop -n waydroid -k 2>/dev/null

# 停止服务
sudo systemctl stop waydroid-container
```

### 验证已关闭

```bash
waydroid status
```

预期输出：
```
Session:        STOPPED
Container:      STOPPED
```

---

## 常见问题

### Q1: 关闭窗口后 Waydroid 又弹出来

**原因**：你只是关闭了图形界面窗口，但 Waydroid 会话和容器仍在后台运行。

**解决**：使用 `waydroid session stop` 命令完全停止会话。

### Q2: waydroid session start 报错网络错误

**解决**：
```bash
# 确保网桥存在
sudo ip link add name waydroid0 type bridge 2>/dev/null || true
sudo ip link set waydroid0 up

# 启动网络脚本
sudo /usr/lib/waydroid/data/scripts/waydroid-net.sh start
```

### Q3: 无法安装 APK

**解决**：
```bash
# 检查 Waydroid 是否完全启动
waydroid status

# 确保容器正在运行
sudo systemctl start waydroid-container

# 重新尝试安装
waydroid app install /path/to/app.apk
```

### Q4: 图形界面显示异常

**解决**：
```bash
# 检查 Wayland 显示
export WAYLAND_DISPLAY=wayland-0

# 如果使用 X11
export DISPLAY=:0

# 重启会话
waydroid session stop
waydroid session start
```

### Q5: 每次重启 WSL 都要重新配置

**解决**：创建启动脚本 `start-waydroid.sh`：

```bash
#!/bin/bash

echo "启动 Waydroid..."

# 加载模块
sudo modprobe bridge
sudo modprobe ip_tables iptable_filter iptable_nat iptable_mangle nf_nat
sudo modprobe xt_MASQUERADE xt_CHECKSUM nf_conntrack

# 创建网桥
sudo ip link add name waydroid0 type bridge 2>/dev/null || true
sudo ip link set waydroid0 up

# 启动网络
sudo /usr/lib/waydroid/data/scripts/waydroid-net.sh start

# 挂载 binder（如果需要）
if [ ! -e /dev/binder ]; then
    sudo mkdir -p /dev/binderfs
    sudo mount -t binder binder /dev/binderfs 2>/dev/null || true
fi

# 启动 Waydroid
waydroid session start &
sleep 5
waydroid show-full-ui
```

---

## 快捷命令参考

| 命令 | 说明 |
|------|------|
| `waydroid status` | 查看运行状态 |
| `waydroid session start` | 启动会话 |
| `waydroid session stop` | 停止会话 |
| `waydroid show-full-ui` | 显示图形界面 |
| `waydroid app install <apk>` | 安装 APK |
| `waydroid app list` | 列出已安装应用 |
| `waydroid app launch <包名>` | 启动应用 |
| `waydroid shell` | 进入 Waydroid shell |
| `waydroid log` | 查看日志 |

---

*文档生成时间: 2026-04-22*
