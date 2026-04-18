name: Terraform

on:
  push:
    branches: [{{PROD_BRANCH}}]
    paths:
      - "terraform/**"
      - ".github/workflows/terraform.yml"
  pull_request:
    branches: [{{PROD_BRANCH}}]
    paths:
      - "terraform/**"
      - ".github/workflows/terraform.yml"
  workflow_dispatch:
    inputs:
      action:
        description: Terraform action
        required: true
        default: plan
        type: choice
        options:
          - plan
          - apply

env:
  AWS_REGION: {{AWS_REGION}}
  TF_VAR_aws_region: {{AWS_REGION}}

jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0
      - name: Terraform fmt
        run: terraform fmt -check -recursive
      - name: Terraform init
        run: terraform init -input=false
      - name: Terraform validate
        run: terraform validate
      - name: Terraform plan
        run: terraform plan -input=false -no-color -out=tfplan
      - name: Terraform apply
        if: github.event_name == 'push' && github.ref == 'refs/heads/{{PROD_BRANCH}}'
        run: terraform apply -input=false -auto-approve tfplan
