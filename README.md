# Infra-Forge: Manages My Personal Infra

A modular Terraform project for provisioning stuff.

## Project Structure

```
infra-forge/
├── terraform/                     # Terraform configuration
│   ├── modules/aws/compute/       # Reusable EC2 module
│   └── deployments/ps/            # Personal environment
└── ...                            # Other directories
```

## Architecture Decisions

### Terraform Versioning Strategy
We use distinct versioning strategies for modules versus deployments to balance stability with compatibility:

- **Modules (`>= X.Y.Z`)**: Uses a minimum version floor (e.g., `>= 1.14.3`). This allows modules to be flexible and reusable across many different project versions without unnecessary constraints.
- **Deployments (`~> X.Y.Z`)**: Uses a pessimistic constraint (e.g., `~> 1.14.3`). This pins the deployment to a specific minor version to ensure predictable execution and state consistency for environments, while still allowing safe patch updates.

### Build vs. Buy: Custom Modules vs. Public Registry
We have deliberately chosen to build **custom internal modules** (e.g., our `aws/compute` module) rather than using the popular [terraform-aws-modules/ec2-instance](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws) or other community standards.

**Rationale:**
1.  **Simplicity & Control**: Public modules (like the de-facto standard for aws modules mentioned just above) are extremely powerful but come with dozens of variables and complex logic to handle every edge case (Spot, specialized block devices, etc.). Our use case is straightforward, and a lean custom module reduces cognitive load.
2.  **No "Official" Constraint**: AWS does not seem to provide an "official" simple EC2 module (only complex solution blueprints). Since we prioritize lean code over community features for this component, a custom wrapper is the most idiomatic choice.

**Future Migration Path:**
Should our requirements grow in complexity (e.g., needing Spot fleets, complex EBS mappings, or intricate user-data handling), we may refactor our modules to follow the **Facade Pattern**. In that scenario, our local module would effectively become a "wrapper" that configures and calls the `terraform-aws-modules/ec2-instance` module internally, preserving our interface while delegating the heavy lifting to the community standard.

## Modules

This project uses modular architecture. Please refer to individual module documentation for detailed design decisions and usage:

*   **[Compute Module](terraform/modules/aws/compute/README.md):** Provisions EC2 instances and handles Security Groups.
*   **[Key Pair Module](terraform/modules/aws/key-pair/README.md):** Manages SSH identity generation and AWS Key Pair registration. Including analysis on Multi-Region architecture.

## Prerequisites

1. **Terraform** >= 1.0.0: [Install](https://developer.hashicorp.com/terraform/downloads)
2. **AWS CLI** configured: `aws configure`

## Usage

Run commands from the directory:

```bash
cd terraform/deployments/ps/aws
terraform init
terraform plan -out test.tfplan -var-file=my.tfvars
terraform apply test.tfplan
terraform destroy -var-file=my.tfvars
```

## Outputs

| Output | Description |
|--------|-------------|
| `instance_id` | EC2 instance ID |
| `public_ip` | Public IP for SSH |
| `private_key_pem (if one was created)` | SSH private key (sensitive) |

## SSH Access

After `terraform apply`, connect using the associated private key:

```bash
# Save the private key (if one was created)
terraform output -raw private_key_pem > ~/.ssh/$(MY_KEY_NAME).pem
chmod 600 ~/.ssh/$(MY_KEY_NAME).pem

# SSH into the server
ssh -i ~/.ssh/$(MY_KEY_NAME).pem ps@$(terraform output -raw public_ip)
```

## Gotchas

1. **Private Key in State**: The SSH private key (if one was created by terraform) is stored in Terraform state. Keep your state file secure or use a remote backend with encryption.

2. **Security Group**: SSH (port 22) is open to `0.0.0.0/0`. If needed, restrict to your IP.

3. **Default VPC**: Uses the default VPC. Ensure one exists in your region.

4. **Region**: Defaults to `us-east-1`. Override via the `aws_region` variable.

## Cleanup

```bash
cd terraform/deployments/ps/aws
terraform destroy
```

## Extending

- **Add GCP**: Create `terraform/modules/gcp/compute` and `terraform/deployments/ps/gcp`
- **Add Prod**: Create `terraform/deployments/production/aws` with different settings
