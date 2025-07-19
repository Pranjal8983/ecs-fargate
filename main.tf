Here’s a complete Terraform module-based project structure to:
Create a VPC with 2 public and 2 private subnets
Attach an Internet Gateway and NAT Gateway
Deploy a Docker image to ECS Fargate
Attach an Application Load Balancer (ALB) to access the containerized application


---
 Project Structure
ecs-project/├── main.tf├── variables.tf├── outputs.tf├── terraform.tfvars├── backend.tf├── modules/│ ├── vpc/│ ├── ecs/│ └── alb/

---
 Step-by-Step Terraform Code

---
1. main.tf
module "vpc" {  source = "./modules/vpc"  region = var.region}
module "alb" {  source = "./modules/alb"  vpc_id = module.vpc.vpc_id  public_subnets = module.vpc.public_subnets  target_group_arn = module.ecs.target_group_arn}
module "ecs" {  source = "./modules/ecs"  vpc_id = module.vpc.vpc_id  private_subnets = module.vpc.private_subnets  cluster_name = "demo-cluster"  container_image = var.container_image  container_port = var.container_port  alb_listener_arn = module.alb.listener_arn}

---
2. variables.tf
variable "region" {  default = "us-east-1"}
variable "container_image" {  description = "Docker image to deploy"  default = "nginx"}
variable "container_port" {  default = 80}

---
3. terraform.tfvars
region = "us-east-1"container_image = "your-ecr-repo/image:latest"container_port = 80

---
 VPC Module: modules/vpc
main.tf
resource "aws_vpc" "main" {  cidr_block = "10.0.0.0/16"  enable_dns_support = true  enable_dns_hostnames = true}
resource "aws_internet_gateway" "igw" {  vpc_id = aws_vpc.main.id}
resource "aws_subnet" "public" {  count = 2  vpc_id = aws_vpc.main.id  cidr_block = cidrsubnet("10.0.0.0/16", 8, count.index)  availability_zone = data.aws_availability_zones.available.names[count.index]  map_public_ip_on_launch = true}
resource "aws_subnet" "private" {  count = 2  vpc_id = aws_vpc.main.id  cidr_block = cidrsubnet("10.0.0.0/16", 8, count.index + 2)  availability_zone = data.aws_availability_zones.available.names[count.index]}
resource "aws_eip" "nat" {  vpc = true}
resource "aws_nat_gateway" "nat" {  allocation_id = aws_eip.nat.id  subnet_id = aws_subnet.public[0].id}
resource "aws_route_table" "public" {  vpc_id = aws_vpc.main.id
  route {    cidr_block = "0.0.0.0/0"    gateway_id = aws_internet_gateway.igw.id  }}
resource "aws_route_table_association" "public" {  count = 2  subnet_id = aws_subnet.public[count.index].id  route_table_id = aws_route_table.public.id}
resource "aws_route_table" "private" {  vpc_id = aws_vpc.main.id
  route {    cidr_block = "0.0.0.0/0"    nat_gateway_id = aws_nat_gateway.nat.id  }}
resource "aws_route_table_association" "private" {  count = 2  subnet_id = aws_subnet.private[count.index].id  route_table_id = aws_route_table.private.id}
data "aws_availability_zones" "available" {}
outputs.tf
output "vpc_id" {  value = aws_vpc.main.id}
output "public_subnets" {  value = aws_subnet.public[*].id}
output "private_subnets" {  value = aws_subnet.private[*].id}

---
 ECS Fargate Module: modules/ecs
main.tf
resource "aws_ecs_cluster" "this" {  name = var.cluster_name}
resource "aws_ecs_task_definition" "this" {  family = "fargate-task"  requires_compatibilities = ["FARGATE"]  network_mode = "awsvpc"  cpu = "256"  memory = "512"
  container_definitions = jsonencode([    {      name = "app"      image = var.container_image      portMappings = [{        containerPort = var.container_port        protocol = "tcp"      }]    }  ])}
resource "aws_ecs_service" "this" {  name = "fargate-service"  cluster = aws_ecs_cluster.this.id  task_definition = aws_ecs_task_definition.this.arn  launch_type = "FARGATE"  desired_count = 1
  network_configuration {    subnets = var.private_subnets    assign_public_ip = false    security_groups = [aws_security_group.ecs.id]  }
  load_balancer {    target_group_arn = var.target_group_arn    container_name = "app"    container_port = var.container_port  }
  depends_on = [aws_iam_role.ecs_task_execution]}
resource "aws_security_group" "ecs" {  name = "ecs-sg"  description = "Allow traffic to ECS"  vpc_id = var.vpc_id
  ingress {    from_port = var.container_port    to_port = var.container_port    protocol = "tcp"    cidr_blocks = ["0.0.0.0/0"]  }
  egress {    from_port = 0    to_port = 0    protocol = "-1"    cidr_blocks = ["0.0.0.0/0"]  }}
resource "aws_iam_role" "ecs_task_execution" {  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({    Version = "2012-10-17"    Statement = [      {        Effect = "Allow"        Principal = {          Service = "ecs-tasks.amazonaws.com"        }        Action = "sts:AssumeRole"      }    ]  })}
resource "aws_iam_role_policy_attachment" "ecs_policy" {  role = aws_iam_role.ecs_task_execution.name  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"}
variables.tf
variable "vpc_id" {}variable "private_subnets" {}variable "cluster_name" {}variable "container_image" {}variable "container_port" {}variable "alb_listener_arn" {}variable "target_group_arn" {}
outputs.tf
output "target_group_arn" {  value = aws_lb_target_group.this.arn}

---
 ALB Module: modules/alb
main.tf
resource "aws_lb" "this" {  name = "app-alb"  internal = false  load_balancer_type = "application"  security_groups = [aws_security_group.alb.id]  subnets = var.public_subnets}
resource "aws_security_group" "alb" {  name = "alb-sg"  vpc_id = var.vpc_id
  ingress {    from_port = 80    to_port = 80    protocol = "tcp"    cidr_blocks = ["0.0.0.0/0"]  }
  egress {    from_port = 0    to_port = 0    protocol = "-1"    cidr_blocks = ["0.0.0.0/0"]  }}
resource "aws_lb_target_group" "this" {  name = "app-target-group"  port = 80  protocol = "HTTP"  vpc_id = var.vpc_id  target_type = "ip"}
resource "aws_lb_listener" "this" {  load_balancer_arn = aws_lb.this.arn  port = 80  protocol = "HTTP"
  default_action {    type = "forward"    target_group_arn = aws_lb_target_group.this.arn  }}
outputs.tf
output "listener_arn" {  value = aws_lb_listener.this.arn}
output "alb_dns_name" {  value = aws_lb.this.dns_name}

---
 Next Steps
1. Run the following:


terraform initterraform planterraform apply
2. Access the app via ALB DNS:


echo "http://$(terraform output -raw alb.alb_dns_name)"

---
Would you like me to zip this project for download?
