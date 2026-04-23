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
                script {
                    sh '''
                        set -euo pipefail
                        echo "Jenkins workspace: $PWD"
                        
                        if [ ! -f docker-compose.devops.yml ]; then
                            echo "ERROR: docker-compose.devops.yml not found."
                            exit 1
                        fi

                        echo "Setting up network and report directories..."
                        docker network inspect petclinic-devops-net >/dev/null 2>&1 || docker network create petclinic-devops-net
                        mkdir -p burp/reports
                        chmod 777 burp/reports

                        echo "Starting Burp Suite Community web container..."
                        docker compose -f docker-compose.devops.yml up -d --build burpsuite-community

                        echo "Waiting for Web UI to be ready..."
                        sleep 10
                    '''
                    
                    input message: 'PAUSED FOR MANUAL SCAN: Please open http://localhost:6081, start Burp Suite, run your manual scan on petclinic, and save your HTML report to /workspace/reports/burp-report.html. Click Proceed when done!', ok: 'Proceed'

                    sh '''
                        echo "Cleaning up container..."
                        docker compose -f docker-compose.devops.yml rm -fsv burpsuite-community
                        
                        if [ ! -f burp/reports/burp-report.html ]; then
                            echo "<html><body><h1>No report saved during manual step.</h1></body></html>" > burp/reports/burp-report.html
                        fi
                    '''
                }
            }
        }

        stage('Publish Burp HTML Report') {
            steps {
                publishHTML(target: [
                    allowMissing: true,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'burp/reports',
                    reportFiles: 'burp-report.html',
                    reportName: 'Burp Community Report'
                ])
                archiveArtifacts artifacts: 'burp/reports/burp-report.html', allowEmptyArchive: true
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