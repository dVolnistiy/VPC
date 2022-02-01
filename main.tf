terraform {
  required_version = ">=0.15.0"
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true

  tags   = {
    Name = "${var.environment}-vpc"
  }
}

locals {
  public_subnets     = {
    "${var.region}a" = "10.0.11.0/24"
    "${var.region}b" = "10.0.21.0/24" 
  }
  private_subnets    = {
    "${var.region}a" = "10.0.12.0/24"
    "${var.region}b" = "10.0.22.0/24" 
  }
  db_subnets         = {
    "${var.region}a" = "10.0.13.0/24"
    "${var.region}b" = "10.0.23.0/24" 
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

###                                 ###
###    PUBLIC AND PRIVATE SUBNETS   ###
###                                 ###

resource "aws_subnet" "Public" {
  vpc_id                  = aws_vpc.main.id
  count                   = "${length(local.public_subnets)}"
  cidr_block              = "${element(values(local.public_subnets), count.index)}"

  map_public_ip_on_launch = true
  availability_zone       = "${element(keys(local.public_subnets), count.index)}"

  depends_on              = [aws_internet_gateway.igw]

  tags   = {
    Name = "${var.environment}-public-subnet"
  }
}

resource "aws_subnet" "Private" {
  vpc_id                  = aws_vpc.main.id
  count                   = "${length(local.private_subnets)}"
  cidr_block              = "${element(values(local.private_subnets), count.index)}"

  # map_public_ip_on_launch = false
  availability_zone       = "${element(keys(local.private_subnets), count.index)}"

  depends_on              = [aws_internet_gateway.igw]

  tags   = {
    Name = "${var.environment}-private-subnet"
  }
}

resource "aws_subnet" "DB" {
  vpc_id                  = aws_vpc.main.id
  count                   = "${length(local.db_subnets)}"
  cidr_block              = "${element(values(local.db_subnets), count.index)}"

  # map_public_ip_on_launch = false
  availability_zone       = "${element(keys(local.db_subnets), count.index)}"

  depends_on              = [aws_internet_gateway.igw]

  tags   = {
    Name = "${var.environment}-db-subnet"
  }
}

###                         ###
###    ELASTIC IP FOR NAT   ###
###         GATEWAYS        ###
###                         ###

resource "aws_eip" "nat" {
  vpc    = true
  count  = "${length(local.private_subnets)}"

  tags   = {
    Name = "${var.environment}-eip"
  }
}

###                               ###
###    NAT Gateways for Private   ###
###             Subnets           ###
###                               ###

resource "aws_nat_gateway" "gateway" {
  count         = "${length(local.private_subnets)}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.Public.*.id, count.index)}"

  tags   = {
    Name = "${var.environment}-nat"
  }
}

###                               ###
###    ROUTE TABLES FOR SUBNETS   ###
###                               ###

resource "aws_default_route_table" "public" {
  default_route_table_id = "${aws_vpc.main.main_route_table_id}"

  tags   = {
    Name = "${var.environment}-public"
  }
}

resource "aws_route_table" "private" {
  count  = "${length(local.private_subnets)}"
  vpc_id = "${aws_vpc.main.id}"  

  tags   = {
    Name = "${var.environment}-private-route"
  }
}

resource "aws_route_table" "db" {
  vpc_id = "${aws_vpc.main.id}"

  tags = {
    Name = "${var.environment}-db-route"
  }
}

###               ###
###     ROUTES    ###
###               ###

resource "aws_route" "public_ig" {
  count                  = "${length(local.public_subnets)}"
  route_table_id         = "${aws_default_route_table.public.id}"
  gateway_id             = "${aws_internet_gateway.igw.id}"
  destination_cidr_block = "0.0.0.0/0"  
}

resource "aws_route" "private_nat" {
  count          = "${length(local.private_subnets)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
  nat_gateway_id = "${element(aws_nat_gateway.gateway.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
}

###                               ###
###     ROUTE TABLE ASSOCIATION   ###
###                               ###

resource "aws_route_table_association" "public" {
  count          = "${length(local.public_subnets)}"
  subnet_id      = "${element(aws_subnet.Public.*.id, count.index)}"
  route_table_id = "${aws_default_route_table.public.id}" # ???
}

resource "aws_route_table_association" "private" {
  count          = "${length(local.private_subnets)}"
  subnet_id      = "${element(aws_subnet.Private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}

resource "aws_route_table_association" "db" {
  count          = "${length(local.db_subnets)}"
  subnet_id      = "${element(aws_subnet.DB.*.id, count.index)}"
  route_table_id = "${aws_route_table.db.id}"
}

###                          ###
###         FOR TESTS        ###
###                          ###

# resource "aws_security_group" "test" {
#   name        = "test_group"
#   description = "Allow SSH port"
#   vpc_id      = aws_vpc.main.id
  
#   ingress {
#     description = "Port for SSH"
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#     }
# }

# resource "aws_instance" "ec2_public" {
#   count = 2

#   ami                    = "ami-055c6079e3f65e9ac"
#   instance_type          = "t2.micro"
#   key_name               = "my-key"
#   subnet_id              = "${element(aws_subnet.Public.*.id, count.index)}"
#   vpc_security_group_ids = [aws_security_group.test.id]

#   tags = {
#     Name = "Public-${count.index}"
#   }  
# }

# resource "aws_instance" "ec2_private" {
#   count = 2

#   ami                    = "ami-055c6079e3f65e9ac"
#   instance_type          = "t2.micro"
#   key_name               = "my-key"
#   subnet_id              = "${element(aws_subnet.Private.*.id, count.index)}"
#   vpc_security_group_ids = [aws_security_group.test.id]

#   tags = {
#     Name = "Private-${count.index}"
#   }  
# }

# resource "aws_instance" "ec2_db" {
#   count = 2

#   ami                    = "ami-055c6079e3f65e9ac"
#   instance_type          = "t2.micro"
#   key_name               = "my-key"
#   subnet_id              = "${element(aws_subnet.DB.*.id, count.index)}"
#   vpc_security_group_ids = [aws_security_group.test.id]

#   tags = {
#     Name = "DB-${count.index}"
#   }
# }
