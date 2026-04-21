#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$LOG_DIR"
mkdir -p "$BUILD_DIR"

LOG_FILE="$LOG_DIR/03-build-kernel-$(date +%Y%m%d-%H%M%S).log"

WSL_KERNEL_REPO="https://github.com/microsoft/WSL2-Linux-Kernel.git"
KERNEL_DIR="$BUILD_DIR/WSL2-Linux-Kernel"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_progress() {
    echo -e "${BLUE}[PROGRESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   编译 WSL2 Waydroid 内核 v1.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" | tee -a "$LOG_FILE"
}

print_footer() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}========================================${NC}"
}

get_kernel_branch() {
    local kernel_version
    kernel_version=$(uname -r | grep -oP '^\d+\.\d+\.\d+' || echo "5.15.133")
    
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
        log_warning "内核目录已存在"
        read -p "是否重新克隆? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除旧目录..."
            rm -rf "$KERNEL_DIR"
        else
            log_info "使用现有内核源码"
            cd "$KERNEL_DIR"
            git fetch origin
            git checkout "$branch" 2>/dev/null || git checkout -b "$branch" origin/"$branch"
            return 0
        fi
    fi
    
    log_info "开始克隆（这可能需要几分钟）..."
    if git clone --depth 1 --branch "$branch" "$WSL_KERNEL_REPO" "$KERNEL_DIR" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "内核源码克隆完成"
        echo "KERNEL_CLONE_SUCCESS=true" >> "$LOG_FILE"
    else
        log_error "内核源码克隆失败"
        echo "KERNEL_CLONE_SUCCESS=false" >> "$LOG_FILE"
        return 1
    fi
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
    
    local config_options=(
        "CONFIG_ANDROID=y"
        "CONFIG_ANDROID_BINDER_IPC=y"
        "CONFIG_ANDROID_BINDERFS=y"
        "CONFIG_ASHMEM=y"
        "CONFIG_ANDROID_BINDER_DEVICES=\"binder,hwbinder,vndbinder\""
        "CONFIG_MEMCG=y"
        "CONFIG_CGROUP_DEVICE=y"
    )
    
    for option in "${config_options[@]}"; do
        local key
        key=$(echo "$option" | cut -d'=' -f1)
        local value
        value=$(echo "$option" | cut -d'=' -f2-)
        
        if grep -q "^$key=" .config 2>/dev/null; then
            sed -i "s/^$key=.*/$option/" .config
            log_success "更新配置: $option"
        else
            echo "$option" >> .config
            log_success "添加配置: $option"
        fi
    done
    
    log_info "更新配置依赖..."
    make olddefconfig 2>&1 | tee -a "$LOG_FILE"
    
    log_info "验证关键配置..."
    local all_set=true
    for option in "${config_options[@]}"; do
        local key
        key=$(echo "$option" | cut -d'=' -f1)
        if grep -q "^$key=y" .config || grep -q "^$key=\"" .config; then
            log_success "✓ $key 已启用"
        else
            log_warning "✗ $key 未启用"
            all_set=false
        fi
    done
    
    if [ "$all_set" = true ]; then
        log_success "所有关键配置已启用"
        echo "KERNEL_CONFIG_SUCCESS=true" >> "$LOG_FILE"
    else
        log_warning "部分配置可能未正确设置，但将继续编译"
        echo "KERNEL_CONFIG_SUCCESS=partial" >> "$LOG_FILE"
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
- Ashmem
- Memory Cgroups
- Device Cgroups
EOF
    
    log_success "内核信息已保存: $info_file"
}

main() {
    print_header
    
    log_info "开始编译 WSL2 Waydroid 内核"
    log_info "日志文件: $LOG_FILE"
    log_info "构建目录: $BUILD_DIR"
    echo "" | tee -a "$LOG_FILE"
    
    read -p "确认开始编译? 这将需要 30-60 分钟 (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [ -n "$REPLY" ]; then
        log_info "用户取消编译"
        exit 0
    fi
    
    clone_kernel_source
    echo "" | tee -a "$LOG_FILE"
    
    configure_kernel
    echo "" | tee -a "$LOG_FILE"
    
    compile_kernel
    echo "" | tee -a "$LOG_FILE"
    
    compile_modules
    echo "" | tee -a "$LOG_FILE"
    
    copy_kernel_image
    echo "" | tee -a "$LOG_FILE"
    
    save_kernel_info
    
    echo "" | tee -a "$LOG_FILE"
    log_success "内核编译全部完成"
    log_info "内核文件: $BUILD_DIR/bzImage-waydroid"
    log_info "可以继续执行下一步: bash 04-install-kernel.sh"
    
    print_footer
}

main "$@"
