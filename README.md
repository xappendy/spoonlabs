<<<<<<< HEAD
# Terraform을 사용한 EKS 클러스터 및 Spring Boot 애플리케이션 배포

---

## 개요

이 Terraform 구성은 **Amazon EKS (Elastic Kubernetes Service)** 클러스터와 함께 **Spring Boot 애플리케이션**을 배포합니다. 주요 구성 요소는 다음과 같습니다:

1. **VPC 구성**:
   - 퍼블릭 및 프라이빗 서브넷을 포함한 VPC 생성.
   - NAT 게이트웨이를 사용하여 프라이빗 서브넷에서 인터넷에 접근 가능.

2. **EKS 클러스터**:
   - EKS 클러스터와 관리형 노드 그룹 배포.
   - EKS 및 Kubernetes를 위한 IAM 역할 및 정책 구성.

3. **Spring Boot 애플리케이션**:
   - Kubernetes Deployment 및 Service를 사용하여 Spring Boot 애플리케이션 배포.
   - Application Load Balancer(ALB)를 통해 외부에서 접근 가능.

4. **Helm Provider**:
   - Helm Provider를 사용하여 Kubernetes 리소스를 관리.

---

## 사전 요구사항

1. **Terraform**: 버전 `>= 1.3`
2. **AWS CLI**: 적절한 자격 증명으로 구성.
3. **kubectl**: EKS와 통신하기 위해 설치 및 구성.
4. **Docker**: Spring Boot 애플리케이션 이미지를 빌드하고 ECR에 푸시하기 위해 필요.

---

## 구성 요소

### 1. VPC 구성
- **모듈**: `terraform-aws-modules/vpc/aws`
- **CIDR**: `10.0.0.0/16`
- **서브넷**:
  - 퍼블릭: `10.0.1.0/24`, `10.0.2.0/24`
  - 프라이빗: `10.0.11.0/24`, `10.0.12.0/24`
- **NAT 게이트웨이**: 프라이빗 서브넷을 위한 NAT 게이트웨이 활성화.

### 2. EKS 클러스터
- **모듈**: `terraform-aws-modules/eks/aws`
- **클러스터 이름**: `spoon-eks-cluster`
- **버전**: `1.31`
- **노드 그룹**:
  - 인스턴스 타입: `t3.medium`
  - 원하는 크기: `2`
  - 최소 크기: `1`
  - 최대 크기: `3`

### 3. Spring Boot 애플리케이션
- **네임스페이스**: `spring-app`
- **Deployment**:
  - 이미지: `881116054065.dkr.ecr.ap-northeast-2.amazonaws.com/helloworld:latest`
  - 복제본: `2`
  - 포트: `8080`
- **Service**:
  - 타입: `ClusterIP`
  - ALB를 통해 외부에서 접근 가능.

### 4. Application Load Balancer (ALB)
- **타입**: 인터넷 접근 가능
- **헬스 체크 경로**: `/actuator/health`
- **타겟 타입**: IP

---

## 사용 방법

### 1. 리포지토리 클론
```bash
git clone <repository-url>
cd <repository-folder>
=======
# spoonlabs
>>>>>>> d7750d412bcb84593ff270bada74b9bbc0ffe758
