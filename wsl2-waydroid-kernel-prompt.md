# WSL2 Waydroid 内核编译提示词

## 背景
我需要在 Windows 10/11 的 WSL2 中运行 Waydroid（Android 容器），但 WSL2 默认内核缺少必要的 Android 驱动模块。

## 当前环境
- Windows 版本: Windows 10 专业版 (Build 19045)
- WSL2 已安装，使用 Ubuntu 22.04/24.04 LTS 发行版
- 目标: 编译自定义 WSL2 内核，启用 Waydroid 支持
- 使用场景: Android 应用开发测试、运行特定移动应用等

## 需要启用的内核模块
```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ASHMEM=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_MEMCG=y
CONFIG_CGROUP_DEVICE=y
```

## 任务要求
请提供：

1. **完整的编译步骤**
   - 环境准备（依赖安装）
   - 下载微软 WSL2 内核源码
   - 内核配置修改方法
   - 编译命令和参数
   - 安装和替换方法

2. **自动化脚本**
   - 一键完成所有步骤的 Bash 脚本
   - 包含错误处理和进度提示

3. **验证方法**
   - 如何确认新内核已生效
   - 如何验证 Waydroid 可以正常运行

4. **回滚方案**
   - 如何恢复到默认内核
   - 常见问题排查

## 部署需求
用户需要完成以下部署任务：
1. 检查当前 WSL2 环境状态
2. 编译并安装支持 Waydroid 的自定义内核
3. 配置 WSL2 使用新内核
4. 安装 Waydroid 容器环境
5. 安装指定的 Android APK 应用
6. 启动并验证应用运行

## 注意事项
- 编译时间可能较长（30-60分钟）
- 需要 15-20GB 磁盘空间
- 内核更新后可能需要重新编译
- 不影响 Windows 主系统
- 部署过程中可能需要处理网络代理配置

## 参考资源
- 微软 WSL2 内核源码: https://github.com/microsoft/WSL2-Linux-Kernel
- Waydroid 官方文档: https://docs.waydro.id/
