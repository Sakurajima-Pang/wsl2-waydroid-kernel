#!/bin/bash

# 不使用 set -e 或 trap ERR，避免意外退出
# 保留 DEBUG 选项
if [ "${DEBUG:-0}" = "1" ]; then
    set -x
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/03-build-kernel-$(date +%Y%m%d-%H%M%S).log"

WSL_KERNEL_REPO="https://github.com/microsoft/WSL2-Linux-Kernel.git"

# 检测最佳构建目录
# WSL2 的 / 是 ext4 虚拟硬盘，区分大小写，适合编译内核
# Windows 挂载的 /mnt/c 等是 9p 文件系统，不区分大小写，不适合
get_optimal_build_dir() {
    local project_build_dir="$PROJECT_DIR/build"
    
    # 检查项目目录是否在 WSL 虚拟硬盘上（通过检查文件系统类型）
    local fs_type
    fs_type=$(df -T "$PROJECT_DIR" 2>/dev/null | awk 'NR==2 {print $2}')
    
    if [ "$fs_type" = "ext4" ] || [ "$fs_type" = "tmpfs" ]; then
        # 项目在 WSL 虚拟硬盘上，直接使用
        echo "$project_build_dir"
    else
        # 项目在 Windows 文件系统上，使用 WSL 虚拟硬盘
        local wsl_build_dir="$HOME/.wsl-waydroid-build"
        echo "$wsl_build_dir"
    fi
}

BUILD_DIR="${BUILD_DIR:-$(get_optimal_build_dir)}"
KERNEL_DIR="${KERNEL_DIR:-$BUILD_DIR/WSL2-Linux-Kernel}"

mkdir -p "$BUILD_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[✓] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    echo "[!] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "[✗] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_progress() {
    echo -e "${BLUE}[PROGRESS]${NC} $1"
    echo "[PROGRESS] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_echo() {
    echo "$1"
    echo "$1" >> "$LOG_FILE" 2>/dev/null || true
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   编译 WSL2 Waydroid 内核 v2.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_echo ""
}

print_footer() {
    log_echo ""
    echo -e "${BLUE}========================================${NC}"
}

check_filesystem_case_sensitive() {
    local test_dir="$BUILD_DIR/.fs_test_$(date +%s)"
    mkdir -p "$test_dir"
    touch "$test_dir/TestFile" 2>/dev/null
    touch "$test_dir/testfile" 2>/dev/null
    local file_count
    file_count=$(ls -1 "$test_dir" 2>/dev/null | wc -l)
    rm -rf "$test_dir"
    
    if [ "$file_count" -ne 2 ]; then
        return 1
    fi
    return 0
}

# 检查是否在 WSL 虚拟硬盘上
is_on_wsl_vhd() {
    local path="$1"
    local fs_type
    fs_type=$(df -T "$path" 2>/dev/null | awk 'NR==2 {print $2}')
    
    if [ "$fs_type" = "ext4" ] || [ "$fs_type" = "tmpfs" ]; then
        return 0
    else
        return 1
    fi
}

get_kernel_branch() {
    local kernel_version
    kernel_version=$(uname -r | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || echo "5.15.133")

    if ! echo "$kernel_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        log_warning "无法解析内核版本: $(uname -r)，使用默认版本 5.15.133"
        kernel_version="5.15.133"
    fi

    local major_minor
    major_minor=$(echo "$kernel_version" | cut -d'.' -f1,2)

    case "$major_minor" in
        "5.15")
            echo "linux-msft-wsl-5.15.y"
            ;;
        "6.1")
            echo "linux-msft-wsl-6.1.y"
            ;;
        "6.6")
            echo "linux-msft-wsl-6.6.y"
            ;;
        *)
            log_warning "未识别的内核版本: $major_minor，使用默认分支 5.15.y"
            echo "linux-msft-wsl-5.15.y"
            ;;
    esac
}

clone_kernel_source() {
    log_info "克隆 WSL2 内核源码..."
    log_info "仓库地址: $WSL_KERNEL_REPO"

    local branch
    branch=$(get_kernel_branch)
    log_info "使用分支: $branch"

    if [ -d "$KERNEL_DIR" ]; then
        log_warning "内核目录已存在: $KERNEL_DIR"
        if [ -z "$SKIP_CLONE_CONFIRM" ]; then
            echo -n "是否重新克隆? (y/N): "
            read -r REPLY < /dev/tty 2>/dev/null || read -r REPLY
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除旧目录..."
                rm -rf "$KERNEL_DIR"
            else
                log_info "使用现有内核源码"
                cd "$KERNEL_DIR"
                log_info "获取最新更新..."
                if ! timeout 60 git fetch origin 2>&1 | tee -a "$LOG_FILE"; then
                    log_warning "git fetch 失败或超时，继续使用现有代码"
                fi
                if git rev-parse --verify "$branch" >/dev/null 2>&1; then
                    if ! git checkout "$branch" 2>&1 | tee -a "$LOG_FILE"; then
                        log_warning "切换到本地分支 $branch 失败，继续使用当前分支"
                    else
                        log_success "已切换到本地分支: $branch"
                    fi
                elif git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
                    if ! git checkout -b "$branch" "origin/$branch" 2>&1 | tee -a "$LOG_FILE"; then
                        log_warning "创建并切换到分支 $branch 失败，继续使用当前分支"
                    else
                        log_success "已创建并切换到分支: $branch (跟踪 origin/$branch)"
                    fi
                else
                    log_warning "分支 $branch 不存在于本地或远程，继续使用当前分支"
                fi
                return 0
            fi
        else
            log_info "使用现有内核源码 (SKIP_CLONE_CONFIRM 已设置)"
            return 0
        fi
    fi
    
    log_info "开始克隆（这可能需要几分钟）..."
    log_info "执行命令: git clone --depth 1 --branch $branch $WSL_KERNEL_REPO $KERNEL_DIR"
    
    local clone_output
    local clone_exit_code
    
    clone_output=$(git clone --depth 1 --branch "$branch" "$WSL_KERNEL_REPO" "$KERNEL_DIR" 2>&1)
    clone_exit_code=$?
    
    echo "$clone_output" | tee -a "$LOG_FILE"
    
    if [ $clone_exit_code -eq 0 ]; then
        log_success "内核源码克隆完成"
        echo "KERNEL_CLONE_SUCCESS=true" >> "$LOG_FILE"
        
        local dir_size
        dir_size=$(du -sh "$KERNEL_DIR" 2>/dev/null | cut -f1 || echo "未知")
        log_info "克隆目录大小: $dir_size"
    else
        log_error "内核源码克隆失败 (退出码: $clone_exit_code)"
        echo "KERNEL_CLONE_SUCCESS=false" >> "$LOG_FILE"
        
        log_info ""
        log_info "可能的解决方案:"
        log_info "1. 检查网络连接"
        log_info "2. 手动克隆: git clone $WSL_KERNEL_REPO $KERNEL_DIR"
        
        return 1
    fi
}

get_kernel_major_version() {
    local kernel_version
    kernel_version=$(uname -r | sed -E 's/^([0-9]+\.[0-9]+).*/\1/' || echo "5.15")
    echo "$kernel_version"
}

configure_kernel() {
    log_info "配置内核..."
    
    cd "$KERNEL_DIR"
    
    log_info "复制当前内核配置..."
    if [ -f /proc/config.gz ]; then
        zcat /proc/config.gz > .config
        log_success "已从 /proc/config.gz 复制配置"
    elif [ -f "/boot/config-$(uname -r)" ]; then
        cp "/boot/config-$(uname -r)" .config
        log_success "已从 /boot 复制配置"
    else
        log_warning "未找到现有配置，使用默认配置"
        make defconfig 2>&1 | tee -a "$LOG_FILE"
    fi
    
    log_info "启用 Waydroid 所需的内核模块..."
    
    local kernel_major
    kernel_major=$(get_kernel_major_version)
    
    # Waydroid 核心配置（Binder 驱动可以独立于 CONFIG_ANDROID 工作）
    log_info "启用 Binder IPC 驱动..."
    
    # 设置自定义内核版本标识，便于识别
    log_info "设置自定义内核版本标识..."
    local local_version="-waydroid-custom"
    
    # 核心 Binder 配置 - 这些是 Waydroid 必需的
    local binder_options=(
        "CONFIG_ANDROID_BINDER_IPC=y"
        "CONFIG_ANDROID_BINDERFS=y"
        "CONFIG_ANDROID_BINDER_DEVICES=\"binder,hwbinder,vndbinder\""
        "CONFIG_LOCALVERSION=\"$local_version\""
    )
    
    # 内存和 cgroup 配置（按依赖顺序）
    local cgroup_options=(
        "CONFIG_CGROUPS=y"
        "CONFIG_MEMCG=y"
        "CONFIG_SWAP=y"
        "CONFIG_MEMCG_SWAP=y"
        "CONFIG_CGROUP_DEVICE=y"
    )
    
    # 合并所有配置
    local all_options=("${binder_options[@]}" "${cgroup_options[@]}")
    
    if [ "$(echo "$kernel_major < 5.18" | bc)" -eq 1 ]; then
        all_options+=("CONFIG_ASHMEM=y")
        log_info "内核版本 < 5.18，启用 ASHMEM 支持"
    else
        log_info "内核版本 >= 5.18，ASHMEM 已被 memfd 替代，跳过"
    fi
    
    # 应用配置
    for option in "${all_options[@]}"; do
        local key
        key=$(echo "$option" | cut -d'=' -f1)
        
        if grep -q "^# $key is not set" .config 2>/dev/null; then
            # 注释掉的配置，替换为启用
            sed -i "s/^# $key is not set.*/$option/" .config
            log_success "启用配置: $option"
        elif grep -q "^$key=" .config 2>/dev/null; then
            # 已存在的配置，更新
            sed -i "s/^$key=.*/$option/" .config
            log_success "更新配置: $option"
        else
            # 不存在的配置，添加
            echo "$option" >> .config
            log_success "添加配置: $option"
        fi
    done
    
    log_info "更新配置依赖..."
    make olddefconfig 2>&1 | tee -a "$LOG_FILE"
    
    log_info "验证关键配置..."
    local all_set=true
    
    # 验证 Binder 核心配置（这些是 Waydroid 真正需要的）
    for option in "${binder_options[@]}"; do
        local key
        key=$(echo "$option" | cut -d'=' -f1)
        if grep -q "^$key=y" .config || grep -q "^$key=\"" .config; then
            log_success "✓ $key 已启用"
        else
            log_warning "✗ $key 未启用"
            all_set=false
        fi
    done
    
    # 验证 cgroup 配置
    for option in "${cgroup_options[@]}"; do
        local key
        key=$(echo "$option" | cut -d'=' -f1)
        if grep -q "^$key=y" .config; then
            log_success "✓ $key 已启用"
        else
            log_warning "✗ $key 未启用"
        fi
    done
    
    if [ "$all_set" = true ]; then
        log_success "Binder 核心配置已启用（Waydroid 可以正常工作）"
        echo "KERNEL_CONFIG_SUCCESS=true" >> "$LOG_FILE"
    else
        log_warning "部分 Binder 配置未启用，尝试强制启用..."
        
        # 使用内核的 config 工具强制启用
        if [ -f scripts/config ]; then
            ./scripts/config --enable CONFIG_ANDROID_BINDER_IPC
            ./scripts/config --enable CONFIG_ANDROID_BINDERFS
            make olddefconfig 2>&1 | tee -a "$LOG_FILE"
            
            # 再次验证
            if grep -q "^CONFIG_ANDROID_BINDER_IPC=y" .config; then
                log_success "Binder IPC 已通过 config 工具启用"
                all_set=true
            fi
        fi
        
        if [ "$all_set" = false ]; then
            log_warning "配置验证未通过，但将继续编译"
            log_info "提示: 编译后可能需要手动检查 binder 支持"
            echo "KERNEL_CONFIG_SUCCESS=partial" >> "$LOG_FILE"
        fi
    fi
    
    cp .config "$BUILD_DIR/kernel-config-backup-$(date +%Y%m%d-%H%M%S)"
    log_success "配置已备份"
}

compile_kernel() {
    log_info "开始编译内核..."
    
    cd "$KERNEL_DIR"
    
    local cpu_cores
    cpu_cores=$(nproc)
    local jobs=$((cpu_cores + 1))
    
    log_info "使用 $jobs 个并行任务进行编译"
    log_info "编译时间预计 30-60 分钟，请耐心等待..."
    log_info "日志输出到: $LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    log_progress "开始编译..."
    
    local start_time
    start_time=$(date +%s)
    
    if make -j"$jobs" 2>&1 | tee -a "$LOG_FILE"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        
        log_success "内核编译完成"
        log_success "编译耗时: ${minutes}分${seconds}秒"
        echo "KERNEL_BUILD_SUCCESS=true" >> "$LOG_FILE"
        echo "BUILD_DURATION=${minutes}m${seconds}s" >> "$LOG_FILE"
    else
        log_error "内核编译失败"
        echo "KERNEL_BUILD_SUCCESS=false" >> "$LOG_FILE"
        return 1
    fi
}

compile_modules() {
    log_info "编译内核模块..."
    
    cd "$KERNEL_DIR"
    
    local cpu_cores
    cpu_cores=$(nproc)
    local jobs=$((cpu_cores + 1))
    
    if make -j"$jobs" modules 2>&1 | tee -a "$LOG_FILE"; then
        log_success "内核模块编译完成"
        echo "MODULES_BUILD_SUCCESS=true" >> "$LOG_FILE"
        
        log_info "安装内核模块到 /lib/modules/..."
        if sudo make modules_install 2>&1 | tee -a "$LOG_FILE"; then
            log_success "内核模块安装完成"
            echo "MODULES_INSTALL_SUCCESS=true" >> "$LOG_FILE"
        else
            log_warning "内核模块安装失败，尝试使用 root 权限..."
            if make modules_install 2>&1 | tee -a "$LOG_FILE"; then
                log_success "内核模块安装完成"
                echo "MODULES_INSTALL_SUCCESS=true" >> "$LOG_FILE"
            else
                log_warning "内核模块安装失败，但这不影响内核镜像的使用"
                log_info "提示: 可以手动运行 'sudo make modules_install' 来安装模块"
                echo "MODULES_INSTALL_SUCCESS=false" >> "$LOG_FILE"
            fi
        fi
    else
        log_warning "内核模块编译出现问题，但内核可能仍可用"
        echo "MODULES_BUILD_SUCCESS=false" >> "$LOG_FILE"
    fi
}

copy_kernel_image() {
    log_info "复制内核镜像..."
    
    local kernel_image
    kernel_image="$KERNEL_DIR/arch/x86/boot/bzImage"
    
    if [ ! -f "$kernel_image" ]; then
        log_error "找不到内核镜像: $kernel_image"
        return 1
    fi
    
    local target_image="$BUILD_DIR/bzImage-waydroid"
    cp "$kernel_image" "$target_image"
    
    local kernel_size
    kernel_size=$(du -h "$target_image" | cut -f1)
    
    log_success "内核镜像已复制: $target_image"
    log_success "内核大小: $kernel_size"
    
    echo "KERNEL_IMAGE=$target_image" >> "$LOG_FILE"
    echo "KERNEL_SIZE=$kernel_size" >> "$LOG_FILE"
}

save_kernel_info() {
    log_info "保存内核信息..."
    
    cd "$KERNEL_DIR"
    
    local kernel_version
    kernel_version=$(make kernelversion 2>/dev/null || echo "unknown")
    
    local info_file="$BUILD_DIR/kernel-info.txt"
    cat > "$info_file" << EOF
WSL2 Waydroid Kernel Build Information
======================================
Build Date: $(date)
Kernel Version: $kernel_version
Source Branch: $(get_kernel_branch)
Source Commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
Build Host: $(uname -a)
Compiler: $(gcc --version | head -1)
Kernel Image: $BUILD_DIR/bzImage-waydroid
Config File: $KERNEL_DIR/.config

Enabled Features:
- Android Binder IPC
- Android BinderFS
- Memory Cgroups
- Device Cgroups
EOF

    local kernel_major
    kernel_major=$(get_kernel_major_version)
    if [ "$(echo "$kernel_major < 5.18" | bc)" -eq 1 ]; then
        echo "- Ashmem" >> "$info_file"
    else
        echo "- Memfd (替代 Ashmem)" >> "$info_file"
    fi
    
    log_success "内核信息已保存: $info_file"
}

main() {
    print_header
    
    log_info "开始编译 WSL2 Waydroid 内核"
    log_info "日志文件: $LOG_FILE"
    log_info "构建目录: $BUILD_DIR"
    log_info "内核目录: $KERNEL_DIR"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 显示文件系统信息
    local fs_type
    fs_type=$(df -T "$BUILD_DIR" 2>/dev/null | awk 'NR==2 {print $2}')
    log_info "构建目录文件系统类型: $fs_type"
    
    if is_on_wsl_vhd "$BUILD_DIR"; then
        log_success "✓ 构建目录位于 WSL 虚拟硬盘 (ext4) 上，支持大小写敏感"
    else
        log_warning "构建目录不在 WSL 虚拟硬盘上"
        log_info "建议将项目移动到 WSL 虚拟硬盘上以获得最佳兼容性:"
        log_info "  cp -r $PROJECT_DIR ~/wsl2-waydroid-kernel"
        log_info "  cd ~/wsl2-waydroid-kernel/scripts"
        log_info "  bash 03-build-kernel.sh"
        log_info ""
        read -p "是否继续? (y/N): " -n 1 -r < /dev/tty 2>/dev/null || read -p "是否继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "用户取消编译"
            exit 0
        fi
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    local current_step=0
    local total_steps=6
    
    show_progress() {
        local step=$1
        local name=$2
        log_info "[$step/$total_steps] $name..."
    }
    
    if [ -z "$SKIP_CONFIRM" ]; then
        log_info "准备开始编译..."
        echo -n "确认开始编译? 这将需要 30-60 分钟 (Y/n): "
        read -r REPLY < /dev/tty 2>/dev/null || read -r REPLY
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "用户取消编译"
            exit 0
        fi
    else
        log_info "跳过确认 (SKIP_CONFIRM 已设置)"
    fi
    
    current_step=$((current_step + 1))
    show_progress $current_step "克隆内核源码"
    if ! clone_kernel_source; then
        log_error "克隆内核源码失败，编译中止"
        print_footer
        exit 1
    fi
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "配置内核"
    configure_kernel
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "编译内核 (这可能需要30-60分钟)"
    if ! compile_kernel; then
        log_error "内核编译失败"
        print_footer
        exit 1
    fi
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "编译内核模块"
    compile_modules
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "复制内核镜像"
    if ! copy_kernel_image; then
        log_error "复制内核镜像失败"
        print_footer
        exit 1
    fi
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "保存内核信息"
    save_kernel_info
    
    echo "" | tee -a "$LOG_FILE"
    log_success "✓ 内核编译全部完成"
    log_info "内核文件: $BUILD_DIR/bzImage-waydroid"
    log_info "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "可以继续执行下一步: bash 04-install-kernel.sh"
    
    print_footer
}

main "$@"
