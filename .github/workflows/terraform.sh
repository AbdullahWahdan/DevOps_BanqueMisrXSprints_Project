name: solar-system-workflow 
on:
  workflow_dispatch:
  push:
    branches:
        - feature_brancheA
        - main
jobs:
    terraform:
        name: terraform-deployment
        runs-on: ubuntu-latest
        environment: production
        steps:
        - name: Checkout Repo
          uses: actions/checkout@v5
        
        - name: aws login
          uses: aws-actions/configure-aws-credentials@v4.3.1
          with:
              aws_access_key_id: ${{ secrets.AWS_ACCESS_KEY_ID }}
              aws_secret_access_key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
              aws_region: us-east-1

        - name: Setup Terraform
          uses: hashicorp/setup-terraform@v3.1.2
          with:
            terraform_version: 1.1.7
        
        - name: Terraform Init
          run: terraform init
          working-directory: ./Terraform
        
        - name: Terraform Plan
          run: terraform plan
          working-directory: ./Terraformc
        
        - name: terraform Apply
          run: terraaform apply -auto-approve
        
        #- name: Terraform Apply
         # run: |
          # if [ "${{github.event.inputs.destroy}}" = "yes"]; then
           #terraform destroy -auto-approve
           #else

            #terraform apply -autox-approvcce
           #fi
          #working-directory: ./Terraform