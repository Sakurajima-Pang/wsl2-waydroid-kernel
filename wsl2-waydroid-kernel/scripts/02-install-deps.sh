#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/02-install-deps-$(date +%Y%m%d-%H%M%S).log"

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
    echo -e "${BLUE}   安装编译依赖 v2.0.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" | tee -a "$LOG_FILE"
}

print_footer() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}========================================${NC}"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"'
    else
        echo "unknown"
    fi
}

update_package_list() {
    log_info "更新软件包列表..."
    
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian)
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
            ;;
        fedora)
            sudo dnf check-update 2>&1 | tee -a "$LOG_FILE" || true
            ;;
        arch)
            sudo pacman -Sy 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            log_warning "未知的发行版，尝试使用 apt"
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE"
            ;;
    esac
    
    log_success "软件包列表已更新"
}

install_dependencies() {
    log_info "安装编译依赖..."
    
    local distro
    distro=$(detect_distro)
    
    local packages_ubuntu=(
        build-essential
        flex
        bison
        libssl-dev
        libelf-dev
        bc
        dwarves
        cpio
        kmod
        libncurses5-dev
        libncursesw5-dev
        git
        wget
        curl
        python3
        python3-pip
        fakeroot
        gnupg2
        lsb-release
        software-properties-common
        apt-transport-https
        ca-certificates
    )
    
    local packages_fedora=(
        make
        gcc
        gcc-c++
        flex
        bison
        openssl-devel
        elfutils-libelf-devel
        bc
        dwarves
        cpio
        kmod
        ncurses-devel
        git
        wget
        curl
        python3
        python3-pip
        fakeroot
        gnupg2
        redhat-lsb-core
    )
    
    local packages_arch=(
        base-devel
        flex
        bison
        openssl
        libelf
        bc
        dwarves
        cpio
        kmod
        ncurses
        git
        wget
        curl
        python
        python-pip
        fakeroot
        gnupg
        lsb-release
    )
    
    case "$distro" in
        ubuntu|debian)
            log_info "安装 Ubuntu/Debian 依赖包..."
            sudo apt-get install -y "${packages_ubuntu[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
        fedora)
            log_info "安装 Fedora 依赖包..."
            sudo dnf install -y "${packages_fedora[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
        arch)
            log_info "安装 Arch Linux 依赖包..."
            sudo pacman -S --needed "${packages_arch[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
        *)
            log_warning "未知的发行版，尝试安装 Ubuntu 依赖"
            sudo apt-get install -y "${packages_ubuntu[@]}" 2>&1 | tee -a "$LOG_FILE"
            ;;
    esac
    
    log_success "依赖包安装完成"
}

verify_installation() {
    log_info "验证安装..."
    
    local tools=(
        "gcc:gcc --version"
        "make:make --version"
        "flex:flex --version"
        "bison:bison --version"
        "git:git --version"
        "bc:bc --version"
    )
    
    local all_installed=true
    
    for tool_info in "${tools[@]}"; do
        IFS=':' read -r tool_name check_cmd <<< "$tool_info"
        if eval "$check_cmd" > /dev/null 2>&1; then
            local version
            version=$(eval "$check_cmd" 2>/dev/null | head -1)
            log_success "$tool_name: $version"
        else
            log_error "$tool_name: 未安装"
            all_installed=false
        fi
    done
    
    if [ "$all_installed" = true ]; then
        log_success "所有工具验证通过"
        return 0
    else
        log_error "部分工具未正确安装"
        return 1
    fi
}

check_compiler_version() {
    log_info "检查编译器版本..."
    
    local gcc_version
    gcc_version=$(gcc --version | head -1)
    log_success "GCC: $gcc_version"
    
    local make_version
    make_version=$(make --version | head -1)
    log_success "Make: $make_version"
    
    echo "GCC_VERSION=$gcc_version" >> "$LOG_FILE"
    echo "MAKE_VERSION=$make_version" >> "$LOG_FILE"
}

main() {
    print_header
    
    log_info "开始安装编译依赖..."
    log_info "日志文件: $LOG_FILE"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "" | tee -a "$LOG_FILE"
    
    local current_step=0
    local total_steps=4
    
    show_progress() {
        local step=$1
        local name=$2
        log_info "[$step/$total_steps] $name..."
    }
    
    current_step=$((current_step + 1))
    show_progress $current_step "更新软件包列表"
    update_package_list
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "安装依赖包"
    install_dependencies
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "检查编译器版本"
    check_compiler_version
    echo "" | tee -a "$LOG_FILE"
    
    current_step=$((current_step + 1))
    show_progress $current_step "验证安装"
    if verify_installation; then
        echo "" | tee -a "$LOG_FILE"
        log_success "✓ 所有依赖安装完成"
        log_info "可以继续执行下一步: bash 03-build-kernel.sh"
        log_info "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        print_footer
        exit 0
    else
        echo "" | tee -a "$LOG_FILE"
        log_error "✗ 依赖安装验证失败"
        log_info "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        print_footer
        exit 1
    fi
}

main "$@"
