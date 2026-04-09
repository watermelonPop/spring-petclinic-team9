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
                    // This command finds the internal Docker IP of the postgres container
                    def postgresIp = sh(script: "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' petclinic-postgres-integration", returnStdout: true).trim()
                    echo "Found Postgres at IP: ${postgresIp}"
                    
                    sh """
                        ./mvnw test \
                            -Dtest=PostgresIntegrationTests \
                            -Dspring.profiles.active=postgres \
                            -Dspring.datasource.url=jdbc:postgresql://${postgresIp}:5432/petclinic \
                            -Dspring.datasource.username=petclinic \
                            -Dspring.datasource.password=petclinic \
                            -Dspring.docker.compose.skip.in-tests=true \
                            -Dcheckstyle.skip
                    """
                }
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