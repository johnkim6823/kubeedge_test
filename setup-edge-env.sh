#!/usr/bin/env bash

################################################################################
# setup-edge-env.sh
#
# Ubuntu 22.04 환경에서 Kubernetes(k3s) + KubeEdge 기반 Edge 환경 설치 스크립트
#
# 사용법:
#   - Master 노드: sudo ./setup-edge-env.sh -master
#   - Worker 노드: sudo ./setup-edge-env.sh -worker
################################################################################

set -euo pipefail

# 전역 변수
KUBEEDGE_VERSION="v1.15.0"
CLOUDCORE_PORT="${CLOUDCORE_PORT:-10000}"

################################################################################
# 로깅 함수
################################################################################

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

################################################################################
# 사전 검증 함수들
################################################################################

# Usage 메시지 출력
usage() {
    cat << EOF
Usage: $0 [-master | -worker]

Options:
  -master   마스터(CloudCore) 노드로 설정
  -worker   워커(EdgeCore) 노드로 설정

Example:
  sudo $0 -master
  sudo $0 -worker
EOF
    exit 1
}

# Root 권한 체크
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다."
        log_error "다음과 같이 실행하세요: sudo $0"
        exit 1
    fi
}

# Ubuntu 22.04 체크
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release 파일이 없습니다."
        exit 1
    fi

    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "22.04" ]]; then
        log_error "이 스크립트는 Ubuntu 22.04에서만 동작합니다."
        log_error "현재 OS: $ID $VERSION_ID"
        exit 1
    fi

    log "OS 검증 완료: Ubuntu 22.04"
}

################################################################################
# 공통 설치 함수들
################################################################################

# 공통 패키지 설치
install_common_packages() {
    log "공통 패키지 설치 시작..."

    apt-get update -qq
    apt-get install -y \
        curl \
        wget \
        jq \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release

    log "공통 패키지 설치 완료"
}

# 노드의 Primary IP 주소 추출
get_primary_ip() {
    hostname -I | awk '{print $1}'
}

# keadm 설치
install_keadm() {
    if command -v keadm &> /dev/null; then
        log "keadm이 이미 설치되어 있습니다. 설치를 스킵합니다."
        return 0
    fi

    log "keadm 설치 시작 (버전: ${KUBEEDGE_VERSION})..."

    local download_url="https://github.com/kubeedge/kubeedge/releases/download/${KUBEEDGE_VERSION}/kubeedge-${KUBEEDGE_VERSION}-linux-amd64.tar.gz"
    local tmp_dir="/tmp/kubeedge-install"

    mkdir -p "${tmp_dir}"

    log "다운로드: ${download_url}"
    wget -q -O "${tmp_dir}/kubeedge.tar.gz" "${download_url}"

    log "압축 해제 중..."
    tar -xzf "${tmp_dir}/kubeedge.tar.gz" -C "${tmp_dir}"

    log "keadm 바이너리 복사..."
    cp "${tmp_dir}/kubeedge-${KUBEEDGE_VERSION}-linux-amd64/keadm/keadm" /usr/local/bin/keadm
    chmod +x /usr/local/bin/keadm

    rm -rf "${tmp_dir}"

    log "keadm 설치 완료: $(keadm version)"
}

################################################################################
# Master 모드 함수들
################################################################################

# k3s server 설치
install_k3s_server() {
    if systemctl is-active --quiet k3s; then
        log "k3s server가 이미 실행 중입니다. 설치를 스킵합니다."
        return 0
    fi

    if command -v k3s &> /dev/null; then
        log "k3s가 이미 설치되어 있습니다. 서비스를 시작합니다."
        systemctl enable k3s
        systemctl start k3s
        return 0
    fi

    log "k3s server 설치 시작..."

    curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644

    systemctl enable k3s
    systemctl start k3s

    log "k3s server 설치 완료"
    systemctl status k3s --no-pager || true

    # k3s가 준비될 때까지 대기
    log "k3s API 서버가 준비될 때까지 대기 중..."
    local retry=0
    while [[ $retry -lt 30 ]]; do
        if k3s kubectl get nodes &> /dev/null; then
            log "k3s API 서버 준비 완료"
            break
        fi
        sleep 2
        retry=$((retry + 1))
    done
}

# CloudCore 초기화
init_cloudcore() {
    if pgrep -f cloudcore &> /dev/null; then
        log "CloudCore가 이미 실행 중입니다. 초기화를 스킵합니다."
        return 0
    fi

    local node_ip
    node_ip=$(get_primary_ip)

    log "CloudCore 초기화 시작 (advertise-address: ${node_ip})..."

    keadm init \
        --advertise-address="${node_ip}" \
        --kube-config=/etc/rancher/k3s/k3s.yaml

    log "CloudCore 초기화 완료"

    # CloudCore 상태 확인
    sleep 3
    if pgrep -f cloudcore &> /dev/null; then
        log "CloudCore가 정상적으로 실행 중입니다."
    else
        log_error "CloudCore 프로세스를 찾을 수 없습니다."
    fi
}

# Master 노드 정보 출력
print_master_info() {
    local node_ip
    node_ip=$(get_primary_ip)

    local k3s_token=""
    if [[ -f /var/lib/rancher/k3s/server/node-token ]]; then
        k3s_token=$(cat /var/lib/rancher/k3s/server/node-token)
    fi

    log "=========================================="
    log "Master 노드 설정 완료!"
    log "=========================================="
    log ""
    log "Worker 노드에서 사용할 정보:"
    log ""
    log "  K3S_URL=https://${node_ip}:6443"
    log "  K3S_TOKEN=${k3s_token}"
    log ""
    log "  CLOUDCORE_IP=${node_ip}"
    log "  CLOUDCORE_PORT=${CLOUDCORE_PORT}"
    log ""
    log "Worker 노드에서 다음과 같이 실행하세요:"
    log ""
    log "  export K3S_URL=https://${node_ip}:6443"
    log "  export K3S_TOKEN=${k3s_token}"
    log "  export CLOUDCORE_IP=${node_ip}"
    log "  sudo -E ./setup-edge-env.sh -worker"
    log ""
    log "=========================================="
}

# Master 모드 메인 함수
setup_master() {
    log "=========================================="
    log "Master 노드 설정 시작"
    log "=========================================="

    install_common_packages
    install_k3s_server
    install_keadm
    init_cloudcore
    print_master_info
}

################################################################################
# Worker 모드 함수들
################################################################################

# k3s agent 설치
install_k3s_agent() {
    if systemctl is-active --quiet k3s-agent || systemctl is-active --quiet k3s; then
        log "k3s agent가 이미 실행 중입니다. 설치를 스킵합니다."
        return 0
    fi

    if command -v k3s &> /dev/null; then
        log "k3s가 이미 설치되어 있습니다."
        return 0
    fi

    # K3S_URL과 K3S_TOKEN 확인 및 입력
    if [[ -z "${K3S_URL:-}" ]]; then
        read -rp "Enter k3s server URL (e.g. https://<master-ip>:6443): " K3S_URL
        export K3S_URL
    fi

    if [[ -z "${K3S_TOKEN:-}" ]]; then
        read -rp "Enter k3s server token: " K3S_TOKEN
        export K3S_TOKEN
    fi

    log "k3s agent 설치 시작..."
    log "  K3S_URL: ${K3S_URL}"
    log "  K3S_TOKEN: ${K3S_TOKEN:0:20}..."

    curl -sfL https://get.k3s.io | K3S_URL="${K3S_URL}" K3S_TOKEN="${K3S_TOKEN}" sh -

    log "k3s agent 설치 완료"

    # 설치된 서비스 확인
    if systemctl list-units --type=service | grep -q k3s-agent; then
        systemctl status k3s-agent --no-pager || true
    else
        systemctl status k3s --no-pager || true
    fi
}

# EdgeCore join
join_edgecore() {
    if pgrep -f edgecore &> /dev/null; then
        log "EdgeCore가 이미 실행 중입니다. join을 스킵합니다."
        return 0
    fi

    # CLOUDCORE_IP 확인 및 입력
    if [[ -z "${CLOUDCORE_IP:-}" ]]; then
        read -rp "Enter CloudCore IP (master node IP): " CLOUDCORE_IP
        export CLOUDCORE_IP
    fi

    # Edge 노드 이름 설정
    local edgenode_name="${EDGENODE_NAME:-$(hostname)}"

    local cloudcore_ipport="${CLOUDCORE_IP}:${CLOUDCORE_PORT}"

    log "EdgeCore join 시작..."
    log "  CloudCore IP:Port: ${cloudcore_ipport}"
    log "  Edge Node Name: ${edgenode_name}"

    # k3s kubeconfig 경로 확인
    local kubeconfig="/etc/rancher/k3s/k3s.yaml"
    if [[ ! -f "${kubeconfig}" ]]; then
        log_error "k3s kubeconfig 파일이 없습니다: ${kubeconfig}"
        log_error "k3s agent가 정상적으로 설치되었는지 확인하세요."
        exit 1
    fi

    keadm join \
        --cloudcore-ipport="${cloudcore_ipport}" \
        --edgenode-name="${edgenode_name}" \
        --kubeedge-version="${KUBEEDGE_VERSION}" \
        --kube-config="${kubeconfig}"

    log "EdgeCore join 완료"

    # EdgeCore 상태 확인
    sleep 3
    if pgrep -f edgecore &> /dev/null; then
        log "EdgeCore가 정상적으로 실행 중입니다."
    else
        log_error "EdgeCore 프로세스를 찾을 수 없습니다."
    fi
}

# Worker 노드 정보 출력
print_worker_info() {
    log "=========================================="
    log "Worker 노드 설정 완료!"
    log "=========================================="
    log ""
    log "노드 이름: ${EDGENODE_NAME:-$(hostname)}"
    log ""
    log "Master 노드에서 다음 명령으로 노드 상태를 확인할 수 있습니다:"
    log "  kubectl get nodes"
    log ""
    log "=========================================="
}

# Worker 모드 메인 함수
setup_worker() {
    log "=========================================="
    log "Worker 노드 설정 시작"
    log "=========================================="

    install_common_packages
    install_k3s_agent
    install_keadm
    join_edgecore
    print_worker_info
}

################################################################################
# 메인 실행 로직
################################################################################

main() {
    # 인자 체크
    if [[ $# -ne 1 ]]; then
        usage
    fi

    local mode="$1"

    # Root 권한 체크
    check_root

    # Ubuntu 22.04 체크
    check_ubuntu_version

    # 모드에 따라 실행
    case "$mode" in
        -master)
            setup_master
            ;;
        -worker)
            setup_worker
            ;;
        *)
            log_error "알 수 없는 옵션: $mode"
            usage
            ;;
    esac

    log ""
    log "모든 작업이 완료되었습니다!"
}

# 스크립트 실행
main "$@"
