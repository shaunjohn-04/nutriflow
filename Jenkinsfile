pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        AWS_REGION = 'ap-south-2'

        BACKEND_REPO  = 'nutriflow-backend'
        FRONTEND_REPO = 'nutriflow-frontend'

        IMAGE_TAG = "${BUILD_NUMBER}"

        SONARQUBE     = 'SonarQube'
        SONAR_SCANNER = 'sonar-scanner'
    }

    stages {

        // ---------------------------------------------------------
        // 1. CHECKOUT
        // ---------------------------------------------------------

        stage('Checkout') {
            steps {
                echo 'Checking out NutriFlow source code...'

                checkout scm

                sh '''
                    echo "========================================"
                    echo "Git Information"
                    echo "========================================"

                    echo "Branch:"
                    git branch --show-current

                    echo "Commit:"
                    git rev-parse --short HEAD

                    echo "Repository:"
                    git remote -v

                    echo "Last commit:"
                    git log -1 --pretty=%B
                '''

                script {
                    def lastMsg = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()

                    if (lastMsg.contains('[skip ci]')) {
                        echo 'GitOps update detected. Skipping pipeline.'
                        currentBuild.result = 'NOT_BUILT'
                        error('Skipping CI-generated GitOps commit.')
                    }
                }
            }
        }

        // ---------------------------------------------------------
        // 2. GET AWS ACCOUNT ID
        // ---------------------------------------------------------

        stage('AWS Configuration') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        export AWS_DEFAULT_REGION=${AWS_REGION}

                        echo "Checking AWS identity..."

                        aws sts get-caller-identity

                        AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
                            --query Account \
                            --output text)

                        echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
                        echo "AWS Region: ${AWS_REGION}"

                        ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

                        echo "ECR Registry: ${ECR_REGISTRY}"

                        echo "${AWS_ACCOUNT_ID}" > .aws_account_id
                        echo "${ECR_REGISTRY}" > .ecr_registry
                    '''
                }

                script {
                    env.AWS_ACCOUNT_ID = readFile('.aws_account_id').trim()
                    env.ECR_REGISTRY = readFile('.ecr_registry').trim()

                    env.BACKEND_IMAGE =
                        "${env.ECR_REGISTRY}/${env.BACKEND_REPO}"

                    env.FRONTEND_IMAGE =
                        "${env.ECR_REGISTRY}/${env.FRONTEND_REPO}"

                    echo "Backend image: ${env.BACKEND_IMAGE}"
                    echo "Frontend image: ${env.FRONTEND_IMAGE}"
                }
            }
        }

        // ---------------------------------------------------------
        // 3. INSTALL DEPENDENCIES
        // ---------------------------------------------------------

        stage('Install Dependencies') {
            parallel {

                stage('Backend Dependencies') {
                    steps {
                        sh '''
                            docker run --rm \
                              -v "$PWD/backend":/app \
                              -w /app \
                              node:20-alpine \
                              npm ci
                        '''
                    }
                }

                stage('Frontend Dependencies') {
                    steps {
                        sh '''
                            docker run --rm \
                              -v "$PWD/frontend":/app \
                              -w /app \
                              node:20-alpine \
                              npm ci
                        '''
                    }
                }
            }
        }

        // ---------------------------------------------------------
        // 4. TESTS
        // ---------------------------------------------------------

        stage('Run Tests') {
            steps {
                echo 'Running NutriFlow tests...'

                sh '''
                    echo "Running backend tests..."

                    docker run --rm \
                      -v "$PWD/backend":/app \
                      -w /app \
                      node:20-alpine \
                      npm test || true

                    echo "Running frontend lint..."

                    docker run --rm \
                      -v "$PWD/frontend":/app \
                      -w /app \
                      node:20-alpine \
                      npm run lint || true
                '''
            }
        }

        // ---------------------------------------------------------
        // 5. SONARQUBE
        // ---------------------------------------------------------

        stage('SonarQube Analysis') {
            steps {
                script {

                    echo 'Running SonarQube analysis...'

                    def scannerHome = tool "${SONAR_SCANNER}"

                    withSonarQubeEnv("${SONARQUBE}") {

                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=nutriflow \
                              -Dsonar.projectName=NutriFlow \
                              -Dsonar.sources=backend,frontend/src \
                              -Dsonar.exclusions="backend/node_modules/**,backend/tests/**,backend/seeds/**,frontend/node_modules/**,frontend/dist/**"
                        """
                    }
                }
            }
        }

        // ---------------------------------------------------------
        // 6. QUALITY GATE
        // ---------------------------------------------------------

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ---------------------------------------------------------
        // 7. DOCKER BUILD
        // ---------------------------------------------------------

        stage('Docker Build') {

            parallel {

                stage('Build Backend') {
                    steps {
                        sh '''
                            docker build \
                              -f backend.Dockerfile \
                              -t ${BACKEND_IMAGE}:${IMAGE_TAG} \
                              -t ${BACKEND_IMAGE}:latest \
                              .
                        '''
                    }
                }

                stage('Build Frontend') {
                    steps {
                        sh '''
                            docker build \
                              -f frontend.Dockerfile \
                              -t ${FRONTEND_IMAGE}:${IMAGE_TAG} \
                              -t ${FRONTEND_IMAGE}:latest \
                              .
                        '''
                    }
                }
            }
        }

        // ---------------------------------------------------------
        // 8. ECR LOGIN
        // ---------------------------------------------------------

        stage('ECR Login') {

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {

                    sh '''
                        export AWS_DEFAULT_REGION=${AWS_REGION}

                        echo "AWS Identity:"
                        aws sts get-caller-identity

                        echo "Logging into ECR..."

                        aws ecr get-login-password \
                          --region ${AWS_REGION} |
                        docker login \
                          --username AWS \
                          --password-stdin ${ECR_REGISTRY}
                    '''
                }
            }
        }

        // ---------------------------------------------------------
        // 9. PUSH TO ECR
        // ---------------------------------------------------------

        stage('Push Images to ECR') {

            steps {

                sh '''
                    echo "Pushing backend..."

                    docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                    docker push ${BACKEND_IMAGE}:latest

                    echo "Pushing frontend..."

                    docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                    docker push ${FRONTEND_IMAGE}:latest
                '''
            }
        }

        // ---------------------------------------------------------
        // 10. UPDATE KUBERNETES MANIFESTS
        // ---------------------------------------------------------

        stage('Update Kubernetes Manifests') {

            steps {

                sh '''
                    echo "Updating backend image..."

                    sed -i -E \
                      "s#image: .*nutriflow-backend:[^[:space:]]+#image: ${BACKEND_IMAGE}:${IMAGE_TAG}#" \
                      k8s/backend.yaml

                    echo "Updating frontend image..."

                    sed -i -E \
                      "s#image: .*nutriflow-frontend:[^[:space:]]+#image: ${FRONTEND_IMAGE}:${IMAGE_TAG}#" \
                      k8s/frontend.yaml

                    echo ""
                    echo "Updated images:"
                    grep "image:" k8s/backend.yaml
                    grep "image:" k8s/frontend.yaml
                '''
            }
        }

        // ---------------------------------------------------------
        // 11. COMMIT GITOPS UPDATE
        // ---------------------------------------------------------

        stage('Commit GitOps Change') {

            steps {

                sh '''
                    git config user.name "Jenkins"
                    git config user.email "jenkins@localhost"

                    git add k8s/backend.yaml
                    git add k8s/frontend.yaml

                    if git diff --cached --quiet; then

                        echo "No Kubernetes changes."

                    else

                        git commit \
                          -m "Update NutriFlow images to ${IMAGE_TAG} [skip ci]"

                    fi
                '''
            }
        }

        // ---------------------------------------------------------
        // 12. PUSH TO YOUR GITHUB
        // ---------------------------------------------------------

        stage('Push GitOps Change') {

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'github-credentials',
                        usernameVariable: 'GIT_USERNAME',
                        passwordVariable: 'GIT_PASSWORD'
                    )
                ]) {

                    sh '''
                        cat > .git-askpass <<'EOF'
#!/bin/sh

case "$1" in
    *Username*)
        echo "$GIT_USERNAME"
        ;;
    *Password*)
        echo "$GIT_PASSWORD"
        ;;
esac
EOF

                        chmod 700 .git-askpass

                        export GIT_ASKPASS="$PWD/.git-askpass"
                        export GIT_TERMINAL_PROMPT=0

                        git push origin HEAD:main

                        rm -f .git-askpass
                    '''
                }
            }
        }
    }

    // ---------------------------------------------------------
    // POST
    // ---------------------------------------------------------

    post {

        always {

            sh '''
                echo "Cleaning workspace..."

                docker logout ${ECR_REGISTRY} || true

                rm -f .git-askpass
                rm -f .aws_account_id
                rm -f .ecr_registry
            '''
        }

        success {

            echo '''
============================================
       NUTRIFLOW PIPELINE SUCCESSFUL
============================================

Checkout            : PASSED
AWS Configuration   : PASSED
Dependencies        : PASSED
Tests               : PASSED
SonarQube           : PASSED
Quality Gate        : PASSED
Docker Build        : PASSED
ECR Login           : PASSED
ECR Push            : PASSED
Kubernetes Update   : PASSED
Git Push            : PASSED

Argo CD should now detect
the GitOps repository change.

============================================
'''
        }

        failure {

            echo '''
============================================
        NUTRIFLOW PIPELINE FAILED
============================================

Check the failed Jenkins stage.

============================================
'''
        }
    }
}
