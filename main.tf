terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.3"
}

provider "aws" {
  region = "ap-northeast-2"
}

# ------------------------------------------------------------------------------
# VPC 구성
# ------------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2c"] # 2개의 가용 영역 사용
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = false # 각 Private Subnet에 NAT Gateway 생성
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Environment = "dev"
  }
}

# ------------------------------------------------------------------------------
# EKS 클러스터 및 관리형 노드 그룹 구성
# ------------------------------------------------------------------------------
resource "aws_iam_role" "eks_role" {
  name = "spoons-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "spoon-eks-cluster"
  cluster_version = "1.31"

  cluster_endpoint_public_access  = true  # 🔑 공개 액세스 허용
  cluster_endpoint_private_access = false # 필요시 개인 액세스 활성화

  cluster_security_group_additional_rules = {
    terraform_access = {
      description = "Terraform runner access"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  vpc_id  = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  iam_role_arn = aws_iam_role.eks_role.arn

  create_iam_role = true
  eks_managed_node_group_defaults = {
    create_launch_template = true
    launch_template_version = "$Latest"
  }

  eks_managed_node_groups = {
    general = {
      name_prefix = "general-"
      instance_type = "t3.medium"
      desired_size  = 2
      min_size      = 1
      max_size      = 3

      node_zones = ["ap-northeast-2a", "ap-northeast-2c"]

      tags = {
        Environment = "dev"
        NodeType    = "general"
      }
    }
  }

  tags = {
    Environment = "dev"
  }

  depends_on = [module.vpc]
}

# ------------------------------------------------------------------------------
# Kubernetes Provider 설정
# ------------------------------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  token                  = data.aws_eks_cluster_auth.cluster.token
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# ------------------------------------------------------------------------------
# Helm Provider 설정
# ------------------------------------------------------------------------------
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.cluster.token
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  }
}

# ------------------------------------------------------------------------------
# Spring Boot Deployment 및 Service 구성
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = "spring-app"
  }
}

resource "kubernetes_deployment" "spring_boot_app" {
  metadata {
    name      = "spring-boot-deployment"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app = "spring-boot-app"
    }
  }
  spec {
    replicas = 2 # 원하는 Pod 개수로 변경
    selector {
      match_labels = {
        app = "spring-boot-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "spring-boot-app"
        }
      }
      spec {
        affinity {
          node_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              preference {
                match_expressions {
                  key      = "node_zone"
                  operator = "In"
                  values   = ["ap-northeast-2a", "ap-northeast-2c"]
                }
              }
            }  
          }
        }
        container {
          name  = "my-app-container"
          image = "881116054065.dkr.ecr.ap-northeast-2.amazonaws.com/helloworld:latest" # ECR
          port {
              container_port = 8080
          }
          readiness_probe {
            http_get {
              path = "/actuator/health"
              port = 8080
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }
          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "spring_boot_service" {
  metadata {
    name      = "spring-boot-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app = "spring-boot-app"
    }
    annotations = {
      "kubernetes.io/ingress.class"                  = "alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip" # IP 모드 사용!
      "alb.ingress.kubernetes.io/load-balancer-name" = "spring-boot-alb-ip-mode"
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/actuator/health"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\": 80}]"
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.spring_boot_app.metadata[0].labels.app
    }
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}

# ------------------------------------------------------------------------------
# Application Load Balancer (ALB) 구성 (IP 모드)
# ------------------------------------------------------------------------------
resource "aws_lb" "alb_ip_mode" {
  name               = "spring-boot-alb-ip-mode"
  internal           = false # 인터넷 접근 가능
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_ip_mode.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Environment = "dev"
  }
}

resource "aws_lb_listener" "alb_listener_ip_mode" {
  load_balancer_arn = aws_lb.alb_ip_mode.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.alb_tg_ip_mode.arn # 컨트롤러가 생성할 Target Group 참조
  }
    depends_on = [aws_lb_target_group.alb_tg_ip_mode]
}

resource "aws_lb_target_group" "alb_tg_ip_mode" {
  name     = "spoons-spring-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  target_type = "ip" # 중요: IP 주소 타겟팅 명시

  health_check {
    path                = "/actuator/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3    
  }
}

resource "aws_security_group" "alb_ip_mode" {
  name_prefix = "alb-ip-mode-sg-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 모든 IP에서 접근 허용 (보안 강화를 위해 특정 IP 또는 Security Group으로 제한 필요)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "dev"
  }
}