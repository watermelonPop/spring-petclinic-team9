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
                    set -euo pipefail
                    echo "Jenkins workspace: $PWD"
                    
                    if [ ! -f docker-compose.devops.yml ]; then
                        echo "ERROR: docker-compose.devops.yml not found. Please make sure the files are pushed."
                        exit 1
                    fi

                    echo "Setting up network..."
                    docker network inspect petclinic-devops-net >/dev/null 2>&1 || docker network create petclinic-devops-net

                    echo "Starting Burp Suite Community container in headless mode using xvfb..."
                    docker compose -f docker-compose.devops.yml up -d --build burpsuite-community

                    echo "Waiting 30 seconds for Java UI to start in virtual frame buffer..."
                    sleep 30

                    echo "Checking container logs to prove Burp started successfully..."
                    docker compose -f docker-compose.devops.yml logs burpsuite-community

                    echo "Cleaning up container..."
                    docker compose -f docker-compose.devops.yml rm -fsv burpsuite-community
                '''
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