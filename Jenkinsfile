pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh './mvnw -DskipTests -Dcheckstyle.skip clean package'
                sh '''
                    JAR_FILE=$(ls target/*.jar | grep -v 'original' | head -n 1)
                    cp "$JAR_FILE" target/spring-petclinic.jar
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh './mvnw test -Dtest=!MySqlIntegrationTests,!PostgresIntegrationTests -Dcheckstyle.skip'
            }
        }

        stage('Integration Tests') {
            steps {
                script {
                    sh '''
                        ./mvnw test \
                            -Dtest=PostgresIntegrationTests \
                            -Dspring.profiles.active=postgres \
                            -Dspring.datasource.url=jdbc:postgresql://petclinic-postgres-integration:5432/petclinic \
                            -Dspring.docker.compose.skip.in-tests=true \
                            -Dcheckstyle.skip
                    '''
                }
            }
        }

        stage('Burp Security Scan') {
            steps {
                sh '''
                    set -e
                    mkdir -p burp

                    # Set BURP_TARGET_URL in Jenkins job/environment as needed.
                    # Example: http://192.168.56.10:8080
                    : "${BURP_TARGET_URL:=http://host.docker.internal:8080}"

                    sed "s|http://TARGET_URL_PLACEHOLDER|${BURP_TARGET_URL}|g" \
                        burp/burp-config.yml > burp/burp-config.runtime.yml

                    docker run --rm \
                        --network petclinic-devops-net \
                        -v "$PWD/burp:/burp" \
                        public.ecr.aws/portswigger/ci-scanner:latest \
                        --config-file=/burp/burp-config.runtime.yml || true
                '''
            }
        }

        stage('Publish Burp HTML Report') {
            steps {
                publishHTML(target: [
                    allowMissing: true,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'burp',
                    reportFiles: 'burp-report.html',
                    reportName: 'Burp DAST Report'
                ])
                archiveArtifacts artifacts: 'burp/burp-report.*', allowEmptyArchive: true
            }
        }

        stage('Deploy to Production') {
            steps {
                sh '''
                    ansible-playbook -i ansible/inventory.ini ansible/deploy-petclinic.yml
                '''
            }
        }

        stage('Verify Production Test') {
            steps {
                sh '''
                    curl -f http://192.168.56.10:8080 | grep -i "Welcome"
                '''
            }
        }
    }

    post {
        always {
            junit '**/target/surefire-reports/*.xml'
        }
    }
}