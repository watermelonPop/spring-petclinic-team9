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

        stage('OWASP ZAP Security Scan') {
            steps {
                script {
                    sh '''
                        set -euo pipefail
                        echo "Jenkins workspace: $PWD"
                        
                        echo "Starting Spring Petclinic in background for DAST Scan..."
                        java -jar target/spring-petclinic.jar --server.port=8081 > spring.log 2>&1 &
                        APP_PID=$!
                        
                        echo "Waiting 30 seconds for application to start..."
                        sleep 30
                        
                        echo "Setting up ZAP report directory..."
                        mkdir -p zap-reports
                        chmod 777 zap-reports

                        echo "Running OWASP ZAP Baseline Scan..."
                        # Using 'container:petclinic-jenkins' network so ZAP shares localhost with Jenkins
                        docker run --rm -u root --network container:petclinic-jenkins \\
                            -v "$PWD/zap-reports":/zap/wrk/:rw \\
                            ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \\
                            -t http://localhost:8081 \\
                            -r zap_report.html -I || true
                            
                        echo "Shutting down background Petclinic app..."
                        kill $APP_PID || true
                    '''
                }
            }
        }

        stage('Publish ZAP HTML Report') {
            steps {
                publishHTML(target: [
                    allowMissing: true,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'zap-reports',
                    reportFiles: 'zap_report.html',
                    reportName: 'OWASP ZAP Report'
                ])
                archiveArtifacts artifacts: 'zap-reports/zap_report.html', allowEmptyArchive: true
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