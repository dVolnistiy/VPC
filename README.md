# Amazon VPC created with Terraform

This Virtual Private Cloud is high-available, and if we add ec2 autoscaling group it will work even if one of the availability zones stop works

## Installation

Install [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

Then [install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and [configure](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) aws-cli to provide credentials to Terraform

## Usage

```bash
terraform init
terraform apply
```

