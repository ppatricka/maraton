# -----------------------------------------------------------------------------
# MongoDB VM. Several weaknesses here are REQUIRED by the exercise:
#   - Ubuntu 20.04 (standard support ended April 2025): outdated OS
#   - MongoDB 4.4 (end of life February 2024): outdated database
#   - Public subnet with SSH open to 0.0.0.0/0
#   - IAM role with ec2:* (can create VMs): overly permissive
# MongoDB itself is reachable only from the EKS private subnets and requires auth.
# -----------------------------------------------------------------------------

# Canonical's Ubuntu 20.04 image. AWS marks old AMIs "deprecated", which hides
# them from searches unless include_deprecated is set.
data "aws_ami" "ubuntu_focal" {
  most_recent        = true
  owners             = ["099720109477"] # Canonical
  include_deprecated = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Passwords are generated here and kept (marked sensitive) in HCP Terraform state.
# No special characters, so they can go straight into a mongodb:// URI.
resource "random_password" "mongo_admin" {
  length  = 24
  special = false
}

resource "random_password" "mongo_app" {
  length  = 24
  special = false
}

resource "aws_key_pair" "mongodb" {
  key_name   = "${var.project}-mongodb"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "mongodb" {
  name        = "${var.project}-mongodb"
  description = "MongoDB VM: SSH from anywhere (intentional weakness), MongoDB from EKS only"
  vpc_id      = module.vpc.vpc_id

  # INTENTIONAL WEAKNESS: SSH open to the whole internet.
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MongoDB only from the private subnets. With the AWS VPC CNI, pods get IPs
  # from those same subnets, so this means "only the Kubernetes network".
  ingress {
    description = "MongoDB from the EKS private subnets"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "All outbound (package installs, S3 backups)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM: what the VM itself is allowed to do in AWS -------------------------

resource "aws_iam_role" "mongodb" {
  name = "${var.project}-mongodb-vm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "mongodb" {
  name = "${var.project}-mongodb-vm"
  role = aws_iam_role.mongodb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # INTENTIONAL WEAKNESS: full EC2 control. Anyone on this VM can launch
        # instances, change security groups, snapshot volumes, and so on.
        Sid      = "OverlyPermissiveEc2"
        Effect   = "Allow"
        Action   = "ec2:*"
        Resource = "*"
      },
      {
        # What the VM actually needs: write backups to the bucket.
        Sid      = "WriteBackups"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "mongodb" {
  name = "${var.project}-mongodb-vm"
  role = aws_iam_role.mongodb.name
}

# --- The VM -------------------------------------------------------------------

resource "aws_instance" "mongodb" {
  ami                         = data.aws_ami.ubuntu_focal.id
  instance_type               = var.mongodb_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.mongodb.id]
  key_name                    = aws_key_pair.mongodb.key_name
  iam_instance_profile        = aws_iam_instance_profile.mongodb.name

  # Installs MongoDB 4.4, creates users, enables auth, sets up the daily backup.
  # Note: user data (including these passwords) is readable by anyone with
  # ec2:DescribeInstanceAttribute. Acceptable in the lab; use a secrets manager in production.
  user_data = templatefile("${path.module}/templates/mongodb-setup.sh.tftpl", {
    admin_password = random_password.mongo_admin.result
    app_password   = random_password.mongo_app.result
    app_database   = var.project
    backup_bucket  = aws_s3_bucket.backups.bucket
    aws_region     = var.aws_region
  })
  user_data_replace_on_change = true

  # Require IMDSv2 for the instance metadata service (blocks simple SSRF credential theft).
  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project}-mongodb"
  }
}
