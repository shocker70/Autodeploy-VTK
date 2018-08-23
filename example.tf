# HOW TO RUN:
#
# IMPORTANT: Remember to modify file [variables.tf].
#
#

# VPC to launch instances + subnets into.
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

# Create internet gateway to give subnets access to internet.
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}


# ELB security group.
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # HTTP access-anyware
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}  

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # SSH access from 46.24.199.193
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
    # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Read from file variables.tf
resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# We create the ELB load balancer in subnet.1 :
resource "aws_elb" "web" {
  name = "terraform-example-elb"

  subnets         = ["${aws_subnet.default.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${aws_instance.web.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}


# Collect ami depending on region
variable "amis" {
  type = "map"
  default = {
    "eu-west-3" = "ami-20ee5e5d"
    "us-west-2" = "ami-4b32be2b"
  }
}

# Read from file variables.tf
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

# We use ubuntu AMI, by default user: ubuntu
resource "aws_instance" "web" {
   connection {
     user = "ubuntu"
	 private_key = "${file(var.private_key_path)}"
  }
  
  ami           = "${lookup(var.amis, var.region)}"
  instance_type = "t2.micro"
  
  # SSH keypair created above.
  key_name = "${aws_key_pair.auth.id}"
  
  # Allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  
  subnet_id = "${aws_subnet.default.id}"
  
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
      "sudo service nginx start",
    ]
  }
  
  provisioner "local-exec" {
  	command = "echo ${aws_elb.web.dns_name} > dns_address.txt"
  }
  
}



