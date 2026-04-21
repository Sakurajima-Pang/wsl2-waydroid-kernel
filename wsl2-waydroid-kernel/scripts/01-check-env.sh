#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/01-check-env-$(date +%Y%m%d-%H%M%S).log"

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

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   WSL2 Waydroid 环境检查报告 v1.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" | tee -a "$LOG_FILE"
}

print_footer() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}========================================${NC}"
}

check_wsl_version() {
    log_info "检查 WSL 版本..."
    
    if ! command -v wsl.exe &> /dev/null; then
        log_error "未检测到 WSL，请确保在 WSL 环境中运行此脚本"
        return 1
    fi
    
    local wsl_version
    wsl_version=$(uname -r | grep -i microsoft | wc -l)
    
    if [ "$wsl_version" -eq 0 ]; then
        log_error "当前不是 WSL 环境"
        return 1
    fi
    
    local kernel_release
    kernel_release=$(uname -r)
    
    if echo "$kernel_release" | grep -q "WSL2"; then
        log_success "WSL 版本: 2"
        echo "WSL_VERSION=2" >> "$LOG_FILE"
        return 0
    else
        log_error "WSL 版本: 1 (需要 WSL2)"
        echo "WSL_VERSION=1" >> "$LOG_FILE"
        return 1
    fi
}

check_distribution() {
    log_info "检查发行版信息..."
    
    if [ -f /etc/os-release ]; then
        local distro_name
        local distro_version
        distro_name=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
        distro_version=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2)
        
        log_success "发行版: $distro_name $distro_version"
        echo "DISTRO=$distro_name" >> "$LOG_FILE"
        echo "VERSION=$distro_version" >> "$LOG_FILE"
        
        case "$distro_name" in
            *Ubuntu*)
                log_success "支持的发行版"
                return 0
                ;;
            *Debian*)
                log_warning "Debian 可能兼容，但未完全测试"
                return 0
                ;;
            *)
                log_warning "未测试的发行版，可能不兼容"
                return 0
                ;;
        esac
    else
        log_error "无法获取发行版信息"
        return 1
    fi
}

check_architecture() {
    log_info "检查系统架构..."
    
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64)
            log_success "架构: $arch (支持)"
            echo "ARCH=$arch" >> "$LOG_FILE"
            return 0
            ;;
        aarch64)
            log_success "架构: $arch (支持)"
            echo "ARCH=$arch" >> "$LOG_FILE"
            return 0
            ;;
        *)
            log_error "架构: $arch (不支持)"
            echo "ARCH=$arch" >> "$LOG_FILE"
            return 1
            ;;
    esac
}

check_disk_space() {
    log_info "检查磁盘空间..."
    
    local required_gb=15
    local available_kb
    local available_gb
    
    available_kb=$(df -k "$HOME" | tail -1 | awk '{print $4}')
    available_gb=$((available_kb / 1024 / 1024))
    
    echo "DISK_AVAILABLE_GB=$available_gb" >> "$LOG_FILE"
    
    if [ "$available_gb" -ge "$required_gb" ]; then
        log_success "磁盘空间: ${available_gb}GB 可用 (需要 ${required_gb}GB)"
        return 0
    else
        log_error "磁盘空间: ${available_gb}GB 可用 (需要 ${required_gb}GB)"
        return 1
    fi
}

check_network() {
    log_info "检查网络连接..."
    
    local github_accessible=false
    local timeout=10
    
    if curl -s --max-time "$timeout" https://github.com > /dev/null 2>&1; then
        log_success "GitHub 连接: 正常"
        github_accessible=true
    else
        log_warning "GitHub 连接: 超时或无法访问"
        log_info "建议配置代理以加速下载"
    fi
    
    echo "GITHUB_ACCESSIBLE=$github_accessible" >> "$LOG_FILE"
    
    if curl -s --max-time "$timeout" https://raw.githubusercontent.com > /dev/null 2>&1; then
        log_success "Raw GitHub 连接: 正常"
    else
        log_warning "Raw GitHub 连接: 可能受限"
    fi
    
    return 0
}

check_kernel_version() {
    log_info "检查当前内核版本..."
    
    local kernel_version
    kernel_version=$(uname -r)
    
    log_success "内核版本: $kernel_version"
    echo "KERNEL_VERSION=$kernel_version" >> "$LOG_FILE"
    
    return 0
}

check_memory() {
    log_info "检查内存..."
    
    local total_mem
    local available_mem
    
    if command -v free &> /dev/null; then
        total_mem=$(free -g | awk '/^Mem:/{print $2}')
        available_mem=$(free -g | awk '/^Mem:/{print $7}')
        
        log_success "总内存: ${total_mem}GB"
        log_success "可用内存: ${available_mem}GB"
        
        if [ "$total_mem" -lt 4 ]; then
            log_warning "内存较少，编译可能需要更长时间"
        fi
        
        echo "MEMORY_TOTAL_GB=$total_mem" >> "$LOG_FILE"
        echo "MEMORY_AVAILABLE_GB=$available_mem" >> "$LOG_FILE"
    else
        log_warning "无法获取内存信息"
    fi
    
    return 0
}

check_existing_waydroid() {
    log_info "检查现有 Waydroid 安装..."
    
    if command -v waydroid &> /dev/null; then
        local waydroid_version
        waydroid_version=$(waydroid --version 2>/dev/null || echo "unknown")
        log_warning "Waydroid 已安装 (版本: $waydroid_version)"
        echo "WAYDROID_INSTALLED=true" >> "$LOG_FILE"
        echo "WAYDROID_VERSION=$waydroid_version" >> "$LOG_FILE"
    else
        log_success "Waydroid 未安装"
        echo "WAYDROID_INSTALLED=false" >> "$LOG_FILE"
    fi
    
    return 0
}

main() {
    print_header
    
    local exit_code=0
    local checks_passed=0
    local checks_total=0
    
    ((checks_total++))
    if check_wsl_version; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_distribution; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_architecture; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_disk_space; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_network; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_kernel_version; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_memory; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    ((checks_total++))
    if check_existing_waydroid; then
        ((checks_passed++))
    else
        exit_code=1
    fi
    
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}----------------------------------------${NC}" | tee -a "$LOG_FILE"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}状态: 环境检查通过 ($checks_passed/$checks_total)${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        log_info "可以继续执行下一步: bash 02-install-deps.sh"
    else
        echo -e "${RED}状态: 环境检查未通过 ($checks_passed/$checks_total)${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        log_error "请解决上述问题后再继续"
    fi
    
    print_footer
    
    log_info "日志已保存到: $LOG_FILE"
    
    exit $exit_code
}

main "$@"
