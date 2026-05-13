# IAM role for the bastion instance
resource "aws_iam_role" "bastion_role" {
  name = "${var.name_prefix}bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Attach policies to the bastion instance role
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion_role.name
}

# Instance profile for the bastion instance
resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.name_prefix}bastion-profile"
  role = aws_iam_role.bastion_role.name
}

# Create a custom policy for EKS management with strict permissions
resource "aws_iam_policy" "eks_bastion_policy" {
  name        = "${var.name_prefix}eks-bastion-policy"
  description = "Policy for managing specific EKS cluster with least privilege"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Specific actions for the target cluster - no wildcards
      {
        Effect = "Allow",
        Action = [
          "eks:AccessKubernetesApi",
          "eks:DescribeCluster",
          "eks:DescribeNodegroup",
          "eks:DescribeUpdate",
          "eks:ListNodegroups",
          "eks:ListUpdates",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateNodegroupVersion"
        ],
        Resource = var.eks_cluster_arn
      },
      # Nodegroup specific permissions
      {
        Effect = "Allow",
        Action = [
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateNodegroupVersion"
        ],
        Resource = "${var.eks_cluster_arn}/nodegroup/*"
      },
      # Fargate profile permissions if needed
      {
        Effect = "Allow",
        Action = [
          "eks:DescribeFargateProfile",
          "eks:ListFargateProfiles"
        ],
        Resource = "${var.eks_cluster_arn}/fargateprofile/*"
      },
      # Minimal list permissions - required for basic operations
      {
        Effect = "Allow",
        Action = [
          "eks:ListClusters"
        ],
        Resource = "*"
      }
    ]
  })
  
  tags = var.common_tags
}

# Attach the custom policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_eks_policy" {
  policy_arn = aws_iam_policy.eks_bastion_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# IAM policy for RDS IAM authentication
resource "aws_iam_policy" "rds_cs_connect_policy" {
  name        = "${var.name_prefix}rds-cs-connect-policy"
  description = "Policy to allow IAM authentication to RDS"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [ # nosemgrep: no-iam-resource-exposure
          "rds-db:connect"
        ],
        Resource = [
          "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${var.rds_cluster_resource_id}/*"
        ]
      }
    ]
  })
  
  tags = var.common_tags
}

# Attach the RDS connect policy to the bastion instance role
resource "aws_iam_role_policy_attachment" "bastion_rds_connect" {
  policy_arn = aws_iam_policy.rds_cs_connect_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# Bedrock policy for bastion
resource "aws_iam_policy" "bedrock_bastion_policy" {
  name        = "${var.name_prefix}bedrock-bastion-policy"
  description = "Policy to allow invoking Bedrock models from bastion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
          "bedrock:ListKnowledgeBases",
          "bedrock:GetKnowledgeBase"
        ]
        Resource = [
          # Allow access to all models in the account across all regions
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:model/*",
          # Allow access to all inference profiles in the account across all regions
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
          # Allow access to AWS foundation models
          "arn:aws:bedrock:*::foundation-model/*",
          # Allow operations on all knowledge bases in the account across all regions
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel",
          "bedrock:ListKnowledgeBases"
        ]
        Resource = [
          # These are read-only list operations that require * resource
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })

  tags = var.common_tags
}

# Attach the Bedrock policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_bedrock_attachment" {
  policy_arn = aws_iam_policy.bedrock_bastion_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# Enhanced Secrets Manager policy for bastion
resource "aws_iam_policy" "secrets_manager_bastion_policy" {
  name        = "${var.name_prefix}secrets-manager-bastion-policy"
  description = "Policy to allow access to required secrets from bastion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = var.secrets_manager_arns
      }
    ]
  })

  tags = var.common_tags
}

# Attach the Secrets Manager policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_secrets_manager_attachment" {
  policy_arn = aws_iam_policy.secrets_manager_bastion_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# Redis access policy for bastion
resource "aws_iam_policy" "redis_bastion_policy" {
  name        = "${var.name_prefix}redis-bastion-policy"
  description = "Policy to allow access to Redis rate limiting cluster from bastion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "elasticache:Connect",
          "elasticache:DescribeReplicationGroups",
          "elasticache:DescribeCacheClusters"
        ],
        Resource = [
          var.redis_cluster_arn,
          "arn:aws:elasticache:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })

  tags = var.common_tags
}

# Attach the Redis policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_redis_attachment" {
  policy_arn = aws_iam_policy.redis_bastion_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# SSM Parameter Store read policy for bastion
resource "aws_iam_policy" "ssm_parameter_bastion_policy" {
  name        = "${var.name_prefix}ssm-parameter-bastion-policy"
  description = "Policy to allow reading SSM Parameter Store values from bastion"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/agentic-platform/*"
        ]
      }
    ]
  })

  tags = var.common_tags
}

# Attach the SSM Parameter Store policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_ssm_parameter_attachment" {
  policy_arn = aws_iam_policy.ssm_parameter_bastion_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# ECR policy for the bastion host with least privilege
resource "aws_iam_policy" "ecr_bastion_policy" {
  name        = "${var.name_prefix}ecr-bastion-policy"
  description = "Policy to allow limited ECR operations from bastion host"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Auth token is account-wide, can't be restricted to specific repositories
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      # Specific permissions for repositories with the agentic-platform prefix
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:BatchGetImage"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/agentic-platform-*"
      },
      # Push image permissions, more sensitive so restricting to specific repositories
      {
        Effect = "Allow"
        Action = [
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/agentic-platform-*"
      }
    ]
  })

  tags = var.common_tags
}

# Attach the ECR policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_ecr_attachment" {
  policy_arn = aws_iam_policy.ecr_bastion_policy.arn
  role       = aws_iam_role.bastion_role.name
}

# Attach AWS managed ELB read-only policy to the bastion role
resource "aws_iam_role_policy_attachment" "bastion_elb_readonly_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly"
  role       = aws_iam_role.bastion_role.name
}
