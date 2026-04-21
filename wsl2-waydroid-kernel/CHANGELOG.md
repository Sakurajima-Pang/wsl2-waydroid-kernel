# 变更日志

所有项目的显著变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
并且本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

---

## [1.0.0] - 2026-04-21

### 新增

- 初始版本发布
- 完整的 7 个独立 Bash 脚本，用于自动化 WSL2 Waydroid 内核编译和安装
- `01-check-env.sh` - 环境检查脚本，验证 WSL 版本、磁盘空间、网络连接等
- `02-install-deps.sh` - 依赖安装脚本，支持 Ubuntu/Debian/Fedora/Arch
- `03-build-kernel.sh` - 内核编译脚本，自动克隆微软 WSL2 内核源码并编译
- `04-install-kernel.sh` - 内核安装脚本，配置 Windows 端 `.wslconfig`
- `05-install-waydroid.sh` - Waydroid 安装脚本，包含仓库配置和镜像下载
- `06-verify.sh` - 验证脚本，检查内核模块、binder 设备、Waydroid 状态
- `99-rollback.sh` - 回滚脚本，支持恢复默认内核、清理编译产物、卸载 Waydroid

### 功能特性

- 完整的错误处理和日志记录机制
- 彩色输出和进度提示
- 支持代理配置
- 自动检测系统发行版并适配
- 关键步骤确认提示
- 详细的故障排除指南

### 文档

- `GUIDE.md` - 完整的项目指南，包含详细步骤和故障排除
- `README.md` - 项目简介和快速开始
- `CHANGELOG.md` - 版本变更日志

### 支持的平台

- Ubuntu 22.04/24.04 LTS
- Debian (测试)
- Fedora (测试)
- Arch Linux (测试)

### 内核支持

- Linux 5.15.y (WSL2 默认)
- Linux 6.1.y
- Linux 6.6.y

---

## 版本说明

### 版本号格式

版本号格式：主版本号.次版本号.修订号

- **主版本号**：重大功能更新或架构变更
- **次版本号**：新增功能或重大改进
- **修订号**：问题修复或小幅改进

### 版本状态

- `stable` - 稳定版本，可用于生产环境
- `beta` - 测试版本，可能存在已知问题
- `alpha` - 开发版本，不建议使用

---

## 未来计划

### [1.1.0] - 计划中

- [ ] 支持自动检测并下载最新的 WSL2 内核版本
- [ ] 添加图形化安装界面选项
- [ ] 支持增量编译（仅编译变更部分）
- [ ] 添加更多发行版支持（openSUSE, Gentoo 等）

### [1.2.0] - 计划中

- [ ] 添加 Waydroid 性能优化选项
- [ ] 支持 GPU 加速配置
- [ ] 添加多语言支持
- [ ] 集成测试套件

### [2.0.0] - 远期规划

- [ ] 重构为 Python 脚本，提供更强大的功能
- [ ] 支持 Windows 原生 PowerShell 脚本
- [ ] 提供 GUI 安装程序
- [ ] 支持一键更新内核

---

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进本项目。

### 提交变更

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交变更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 报告问题

请使用 GitHub Issues 报告问题，并包含以下信息：

- 操作系统版本
- WSL 版本
- 执行的脚本和步骤
- 错误信息和日志

---

## 参考

- [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)
- [Semantic Versioning](https://semver.org/lang/zh-CN/)
