# WSL2 Waydroid 内核编译脚本需求

## 目标
为 WSL2 编译支持 Waydroid 的自定义 Linux 内核，提供可在 WSL 中手动运行的 Bash 脚本。

## 当前环境
- Windows 10/11 专业版，WSL2 已启用
- WSL 发行版：Ubuntu 22.04/24.04 LTS
- 用途：在 WSL2 中运行 Android 容器

## 需要的内核模块
```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ASHMEM=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_MEMCG=y
CONFIG_CGROUP_DEVICE=y
```

## 脚本需求

### 1. 环境检查脚本 `01-check-env.sh`
- 检查 WSL 版本和发行版信息
- 检查磁盘空间（需 15GB+）
- 检查网络连接（GitHub 可访问性）
- 输出环境状态报告

### 2. 依赖安装脚本 `02-install-deps.sh`
- 安装编译依赖：build-essential, flex, bison, libssl-dev 等
- 检查并安装必要的工具链
- 配置代理（如需要）

### 3. 内核编译脚本 `03-build-kernel.sh`
- 克隆微软 WSL2 内核源码
- 复制并修改内核配置，启用所需模块
- 编译内核（支持多线程加速）
- 输出编译后的内核文件路径

### 4. 内核安装脚本 `04-install-kernel.sh`
- 备份当前内核（可选）
- 安装编译好的内核到 WSL
- 配置 Windows 端 `.wslconfig` 使用新内核
- 重启 WSL 并验证新内核生效

### 5. Waydroid 安装脚本 `05-install-waydroid.sh`
- 添加 Waydroid 官方仓库
- 安装 Waydroid 及依赖
- 初始化 Waydroid 容器
- 下载 Android 系统镜像

### 6. 验证脚本 `06-verify.sh`
- 检查内核模块是否加载
- 检查 binder 设备是否存在
- 检查 Waydroid 服务状态
- 输出验证报告

### 7. 回滚脚本 `99-rollback.sh`
- 恢复默认内核配置
- 清理编译产物
- 可选：卸载 Waydroid

## 脚本要求
- 每个脚本独立可运行
- 包含详细的进度提示和错误处理
- 支持 `set -e` 严格模式
- 关键步骤有确认提示
- 输出彩色日志便于阅读

## 手动执行流程
```bash
# 按顺序在 WSL 中运行
bash 01-check-env.sh
bash 02-install-deps.sh
bash 03-build-kernel.sh
bash 04-install-kernel.sh
bash 05-install-waydroid.sh
bash 06-verify.sh
```

## 注意事项
- 编译时间：30-60 分钟（取决于硬件）
- 磁盘需求：15-20GB 空闲空间
- 需要管理员权限修改内核
- Windows 端需编辑 `.wslconfig` 文件

## 参考
- WSL2 内核源码：https://github.com/microsoft/WSL2-Linux-Kernel
- Waydroid 文档：https://docs.waydro.id/
