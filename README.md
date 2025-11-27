# KubeEdge Edge Environment Setup Script

Ubuntu 22.04 환경에서 Kubernetes(k3s) + KubeEdge 기반의 Edge 컴퓨팅 환경을 자동으로 구성하는 Bash 스크립트입니다.

## 📋 개요

이 스크립트는 연구 및 개발 목적의 최소 구성 Edge 환경을 빠르게 셋업할 수 있도록 설계되었습니다. 단일 스크립트로 Master(Cloud) 노드와 Worker(Edge) 노드를 모두 설정할 수 있습니다.

### 주요 기능

- ✅ **단일 스크립트** - Master와 Worker 설정을 하나의 스크립트로 처리
- ✅ **Idempotent** - 재실행해도 안전하며, 이미 설치된 구성요소는 스킵
- ✅ **자동화** - IP 주소 자동 감지, 토큰 자동 생성
- ✅ **인터랙티브 모드** - 필요한 정보를 대화형으로 입력 가능
- ✅ **검증 기능** - OS 버전, Root 권한 등 사전 검증 수행

### 설치되는 구성요소

**Master 노드:**
- k3s server (Kubernetes Control Plane)
- KubeEdge keadm
- KubeEdge CloudCore

**Worker 노드:**
- k3s agent (Kubernetes Worker)
- KubeEdge keadm
- KubeEdge EdgeCore

## 🔧 요구사항

### 시스템 요구사항

- **OS**: Ubuntu 22.04 LTS (필수)
- **권한**: Root 또는 sudo 권한
- **네트워크**: 인터넷 연결 필요
- **최소 사양**:
  - CPU: 2 cores 이상
  - RAM: 2GB 이상
  - Disk: 20GB 이상

### 네트워크 요구사항

**Master 노드가 열어야 할 포트:**
- `6443`: k3s API server
- `10000`: KubeEdge CloudCore (기본값)
- `10002`: KubeEdge CloudCore WebSocket

**Worker 노드가 열어야 할 포트:**
- `10250`: kubelet
- `10255`: kubelet read-only

## 🚀 사용법

### 1. Master 노드 설정

Master 노드(Cloud 역할)에서 다음 명령을 실행합니다:

```bash
# 스크립트 다운로드
git clone <repository-url>
cd kubeedge_test

# 실행 권한 부여
chmod +x setup-edge-env.sh

# Master 모드로 실행
sudo ./setup-edge-env.sh -master
```

실행이 완료되면 Worker 노드에서 사용할 정보가 출력됩니다:

```
========================================
Master 노드 설정 완료!
========================================

Worker 노드에서 사용할 정보:

  K3S_URL=https://192.168.1.100:6443
  K3S_TOKEN=K1234567890abcdef::server:1234567890abcdef

  CLOUDCORE_IP=192.168.1.100
  CLOUDCORE_PORT=10000

Worker 노드에서 다음과 같이 실행하세요:

  export K3S_URL=https://192.168.1.100:6443
  export K3S_TOKEN=K1234567890abcdef::server:1234567890abcdef
  export CLOUDCORE_IP=192.168.1.100
  sudo -E ./setup-edge-env.sh -worker

========================================
```

### 2. Worker 노드 설정

Worker 노드(Edge 역할)에서 실행합니다.

#### 방법 1: 환경 변수 사용 (권장)

Master 노드에서 출력된 정보를 환경 변수로 설정하고 실행:

```bash
# Master 노드 정보 설정
export K3S_URL=https://192.168.1.100:6443
export K3S_TOKEN=K1234567890abcdef::server:1234567890abcdef
export CLOUDCORE_IP=192.168.1.100

# Worker 모드로 실행 (-E 옵션으로 환경 변수 유지)
sudo -E ./setup-edge-env.sh -worker
```

#### 방법 2: 인터랙티브 모드

환경 변수 없이 실행하면 스크립트가 필요한 정보를 물어봅니다:

```bash
sudo ./setup-edge-env.sh -worker

# 프롬프트에 따라 입력
# Enter k3s server URL (e.g. https://<master-ip>:6443): https://192.168.1.100:6443
# Enter k3s server token: K1234567890abcdef::server:1234567890abcdef
# Enter CloudCore IP (master node IP): 192.168.1.100
```

### 3. 설치 확인

Master 노드에서 클러스터 상태를 확인합니다:

```bash
# 노드 목록 확인
kubectl get nodes

# 출력 예시:
# NAME           STATUS   ROLES                  AGE   VERSION
# master-node    Ready    control-plane,master   5m    v1.28.x+k3s1
# edge-node-01   Ready    agent                  2m    v1.28.x+k3s1

# KubeEdge 노드 확인
kubectl get nodes -o wide

# CloudCore 상태 확인
systemctl status cloudcore

# Edge 노드에서 EdgeCore 상태 확인
systemctl status edgecore
```

## ⚙️ 고급 설정

### 환경 변수 커스터마이징

스크립트는 다음 환경 변수를 지원합니다:

```bash
# KubeEdge 버전 변경 (기본값: v1.15.0)
export KUBEEDGE_VERSION=v1.16.0

# CloudCore 포트 변경 (기본값: 10000)
export CLOUDCORE_PORT=10000

# Edge 노드 이름 커스터마이징 (기본값: hostname)
export EDGENODE_NAME=my-edge-node-01

# Worker 모드 실행
sudo -E ./setup-edge-env.sh -worker
```

### 여러 Worker 노드 추가

동일한 Master에 여러 Worker 노드를 추가할 수 있습니다:

```bash
# Worker 노드 1
export EDGENODE_NAME=edge-node-01
sudo -E ./setup-edge-env.sh -worker

# Worker 노드 2
export EDGENODE_NAME=edge-node-02
sudo -E ./setup-edge-env.sh -worker

# Worker 노드 3
export EDGENODE_NAME=edge-node-03
sudo -E ./setup-edge-env.sh -worker
```

## 🔍 트러블슈팅

### 1. "이 스크립트는 Ubuntu 22.04에서만 동작합니다" 오류

**원인**: Ubuntu 22.04가 아닌 다른 버전에서 실행

**해결책**: Ubuntu 22.04 LTS 환경에서 실행하거나, 스크립트의 `check_ubuntu_version` 함수를 수정 (권장하지 않음)

### 2. "이 스크립트는 root 권한으로 실행해야 합니다" 오류

**원인**: sudo 없이 실행

**해결책**:
```bash
sudo ./setup-edge-env.sh -master
# 또는
sudo ./setup-edge-env.sh -worker
```

### 3. CloudCore/EdgeCore가 시작되지 않음

**확인 사항**:
```bash
# 로그 확인
journalctl -u cloudcore -f  # Master 노드
journalctl -u edgecore -f   # Worker 노드

# 프로세스 확인
ps aux | grep cloudcore  # Master 노드
ps aux | grep edgecore   # Worker 노드
```

**일반적인 원인**:
- 방화벽이 필요한 포트를 차단
- 네트워크 연결 문제
- IP 주소 자동 감지 실패

**해결책**:
```bash
# 방화벽 확인 및 포트 개방 (ufw 사용 시)
sudo ufw allow 6443/tcp
sudo ufw allow 10000/tcp
sudo ufw allow 10002/tcp

# 서비스 재시작
sudo systemctl restart cloudcore  # Master
sudo systemctl restart edgecore   # Worker
```

### 4. Worker 노드가 클러스터에 조인되지 않음

**확인 사항**:
```bash
# Master 노드에서
kubectl get nodes

# Worker 노드에서
sudo systemctl status k3s-agent
sudo systemctl status edgecore
```

**해결책**:
1. K3S_URL과 K3S_TOKEN이 정확한지 확인
2. Master 노드 IP로 ping 테스트
3. 포트 6443과 10000이 열려있는지 확인

### 5. 스크립트 재실행

스크립트는 idempotent하게 설계되어 재실행이 안전합니다:

```bash
# 안전하게 재실행 가능
sudo ./setup-edge-env.sh -master
sudo -E ./setup-edge-env.sh -worker
```

## 📝 제한사항

이 스크립트는 **연구 및 개발 목적의 최소 구성**을 제공합니다:

- ❌ 프로덕션 환경에 적합하지 않음
- ❌ 고가용성(HA) 구성 미지원
- ❌ 보안 강화 설정 미포함
- ❌ 모니터링 스택(Prometheus, Grafana 등) 미포함
- ❌ 로깅 스택(ELK, Loki 등) 미포함

프로덕션 환경에서는 다음을 추가로 고려해야 합니다:
- TLS/SSL 인증서 구성
- RBAC 정책 강화
- 네트워크 정책 구성
- 리소스 쿼터 및 제한 설정
- 백업 및 복구 전략

## 🧹 환경 제거

설치한 환경을 제거하려면:

```bash
# k3s 제거
sudo /usr/local/bin/k3s-uninstall.sh        # Master 노드
sudo /usr/local/bin/k3s-agent-uninstall.sh  # Worker 노드

# KubeEdge 제거
sudo keadm reset

# keadm 바이너리 제거
sudo rm /usr/local/bin/keadm

# KubeEdge 설정 및 데이터 제거
sudo rm -rf /etc/kubeedge
sudo rm -rf /var/lib/kubeedge
```

## 📚 참고 자료

- [k3s 공식 문서](https://docs.k3s.io/)
- [KubeEdge 공식 문서](https://kubeedge.io/docs/)
- [KubeEdge GitHub](https://github.com/kubeedge/kubeedge)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/)

## 📄 라이선스

이 프로젝트는 연구 및 교육 목적으로 제공됩니다.

## 🤝 기여

버그 리포트나 개선 제안은 이슈로 등록해 주세요.

---

**⚠️ 주의**: 이 스크립트는 Ubuntu 22.04 환경에서만 테스트되었습니다. 다른 환경에서의 동작은 보장하지 않습니다.
