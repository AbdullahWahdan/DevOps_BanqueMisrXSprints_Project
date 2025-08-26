name: solar-system-workflow
on:
  workflow_dispatch:
  push:
    branches:
        - feature_brancheA
        - main
env:
  MONGO_URI: 'mongodb+srv://supercluster.d83jj.mongodb.net/superData'
  MONGO_USERNAME: ${{vars.MONGO_USERNAME}}
  MONGO_PASSWORD: ${{secrets.MONGO_PASSWORD}}

jobs:
  unit_testing:
    name: unit_testing
    strategy:
      matrix:
        nodejs-version: [18, 19, 20]
        os: [ ubuntu-latest, windows-latest, macos-latest ]
        exclude:
        - nodejs-version: 18
          os: macos-latest
    runs-on: ${{ matrix.os }}
    steps:
    - name: Checkout Repo
      uses: actions/checkout@v5

    - name: Set up Node.js - ${{ matrix.nodejs-version }}
      uses: actions/setup-node@v4.4.0
      with:
        node-version: ${{ matrix.nodejs-version }}

    - name: Install Dependencies
      run: npm install

    - name: Run Tests
      id: nodeNodeJs-unit-testing-step
      run: npm test

    - name: archive test results
      if: steps.nodeNodeJs-unit-testing-step.outcome == 'failure' || steps.nodeNodeJs-unit-testing-step.outcome == 'success'
      uses: actions/upload-artifact@v4.6.2
      with:
        name: sp-test-results-${{matrix.os}}-${{matrix.nodejs-version}}
        path: test-results.xml

  code-coverage:
    name: code-coverage
    needs: unit_testing
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repo
        uses: actions/checkout@v5

      - name: Set up Node.js - 18
        uses: actions/setup-node@v4.4.0
        with:
          node-version: 18

      - name: Install Dependencies
        run: npm install

      - name: check Code Coverage
        continue-on-error: true
        run: npm run coverage
      
      - name: archive Coverage results
        uses: actions/upload-artifact@v4.6.2
        with:
          name: code-coverage-results
          path: coverage
          retention-days: 5

  docker:
        name: containerization
        needs: [unit_testing, code-coverage]
        permissions:
            packages: write
            contents: read
        runs-on: ubuntu-latest
        steps:
        - name: Checkout Repo
          uses: actions/checkout@v5
        
        - name: docker login
          uses: docker/login-action@v2
          with:
            username: ${{ vars.DOCKER_USERNAME }}
            password: ${{ secrets.DOCKER_PASSWORD }}

        - name: GHCR Login
          uses: docker/login-action@v2
          with:
            registry: ghcr.io
            username: ${{ github.repository_owner }}
            password: ${{ secrets.GITHUB_TOKEN }}
        
        - name: Build Docker Image
          uses: docker/build-push-action@v4
          with:
            push: false
            tags: ${{vars.DOCKER_USERNAME}}/solar-system:${{github.sha}}
            
        - name: test Image
          run: |
            docker images
            docker run --name solar-system-app -d \
            -p 3000:3000 \
            -e MONGO_URI=$MONGO_URI \
            -e MONGO_USERNAME=$MONGO_USERNAME \
            -e MONGO_PASSWORD=$MONGO_PASSWORD \
            ${{vars.DOCKER_USERNAME}}/solar-system:${{github.sha}}
            export IP_ADDRESS=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' solar-system-app)
            echo $IP
            echo Testing image URL using wget
            wget -q -O - 127.0.0.1:3000/live | grep live

        - name: Build Docker Image
          uses: docker/build-push-action@v4
          with:
            push: true
            tags: |
              ${{vars.DOCKER_USERNAME}}/solar-system:${{github.sha}}
              ghcr.io/abdullahwahdan/solar-system:fd763e67db03ecb5bb601a048c5f913a8ba9bdcb

  terraform:
        name: terraform-deployment
        needs: [docker, code-coverage, unit_testing]
        runs-on: ubuntu-latest
        environment: production
        steps:
        - name: Checkout Repo
          uses: actions/checkout@v5
        
        - name: aws login
          uses: aws-actions/configure-aws-credentials@v4.3.1
          with:
              aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
              aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
              aws-region: us-east-1

        - name: Setup Terraform
          uses: hashicorp/setup-terraform@v3.1.2
          with:
            terraform_version: 1.1.7
        
        - name: terraform init
          run: terraform init
          working-directory: ./Terraform/team-01


        - name: terraform plan
          run: terraform plan
          working-directory: ./Terraform/team-01

        - name: terraform apply or destroy
          run: |
              if [ "${{ github.event.inputs.destroy }}" = "yes" ]; then
              terraform destroy -auto-approve
              else
              terraform apply -auto-approve
              fi
          working-directory: ./Terraform/team-01
  deploy:
        needs: terraform
        name: deploy to EKS
        runs-on: ubuntu-latest

        steps:
            - name: checkout config files
              uses: actions/checkout@v5


            - name: Configure AWS Credentials
              uses: aws-actions/configure-aws-credentials@v4.3.1
              with:
                  aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
                  aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
                  aws-region: us-east-1

            - name: update kubeconfig
              run: | 
                    aws eks --region us-east-1 update-kubeconfig --name sprints-cluster-0
            
            - name: Set up Helm
              uses: azure/setup-helm@v4.2.0
              with:
                version: v3.14.4   

            - name: Deploy using Helm
              run: |
                helm upgrade --install solar-system ./helm \
                  --namespace default \
                  --set image.repository=${{ vars.DOCKER_USERNAME }}/solar-system \
                  --set image.tag=${{ github.sha }} \
                  --set service.type=LoadBalancer \
                  --set env.MONGO_URI="${{ env.MONGO_URI }}" \
                  --set env.MONGO_USERNAME="${{ env.MONGO_USERNAME }}" \
                  --set env.MONGO_PASSWORD="${{ env.MONGO_PASSWORD }}"

            - name: Verify Deployment
              run: |
                kubectl get pods  
                kubectl get svc

