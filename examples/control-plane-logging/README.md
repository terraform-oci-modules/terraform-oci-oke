# OKE control-plane logging

Minimal example: a basic OKE cluster (no node pools) with control-plane
logging enabled through OCI Logging, mirroring EKS's `enabled_log_types` /
`create_cloudwatch_log_group`.

## Usage

```bash
terraform init
terraform plan -var 'compartment_id=<your-compartment-ocid>'
terraform apply -var 'compartment_id=<your-compartment-ocid>'
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
