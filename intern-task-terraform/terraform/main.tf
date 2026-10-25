resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "intern-task-terraform-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "intern-task-terraform-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "intern-task-terraform-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "intern-task-terraform-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "instance" {
  name        = "intern-task-terraform-sg"
  description = "Allow restricted SSH and the application port only."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from the configured trusted CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Intern task application"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic for package installation and image build"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "intern-task-terraform-sg"
  }
}

resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = true

  # Cloud-init runs at first boot. Later user_data changes should not
  # automatically destroy and recreate this instance.
  user_data_replace_on_change = false

  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y docker.io ufw

    systemctl enable --now docker

    if ! id devops >/dev/null 2>&1; then
      useradd --create-home --shell /bin/bash devops
    fi

    usermod -aG docker devops
    printf 'devops ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/devops
    chmod 0440 /etc/sudoers.d/devops
    visudo -cf /etc/sudoers.d/devops

    install -d -m 0755 /opt/intern-task-app/app

    printf '%s' '${base64encode(file("${path.module}/../../intern-task-app/Dockerfile"))}' \
      | base64 -d > /opt/intern-task-app/Dockerfile

    printf '%s' '${base64encode(file("${path.module}/../../intern-task-app/app/app.py"))}' \
      | base64 -d > /opt/intern-task-app/app/app.py

    docker build -t intern-task-app:local /opt/intern-task-app

    cat > /etc/systemd/system/intern-task-app.service <<'SERVICE'
    [Unit]
    Description=Intern Task Application Container
    Requires=docker.service
    After=docker.service

    [Service]
    Restart=always
    RestartSec=5
    ExecStartPre=-/usr/bin/docker stop intern-task-app
    ExecStartPre=-/usr/bin/docker rm intern-task-app
    ExecStart=/usr/bin/docker run --rm --name intern-task-app -p ${var.app_port}:${var.app_port} -e PORT=${var.app_port} intern-task-app:local
    ExecStop=/usr/bin/docker stop -t 10 intern-task-app
    TimeoutStartSec=0

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now intern-task-app.service

    # Keep the host firewall enabled. Permit SSH only from the supplied
    # trusted CIDR and permit the app port; deny other inbound traffic.
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow from ${var.ssh_allowed_cidr} to any port 22 proto tcp
    ufw allow ${var.app_port}/tcp
    ufw --force enable
  USERDATA

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table_association.public
  ]

  tags = {
    Name = "intern-task-terraform-app"
  }
}
