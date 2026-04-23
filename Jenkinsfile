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
        
        stage('SonarQube Analysis') {
            steps {
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh """
                        ./mvnw jacoco:report sonar:sonar \
                            -Dsonar.projectKey=petclinic \
                            -Dsonar.projectName=Petclinic \
                            -Dsonar.host.url=http://sonarqube:9000 \
                            -Dsonar.token=${SONAR_TOKEN} \
                            -Dcheckstyle.skip
                    """
                }
            }
        }

        stage('Verify Monitoring') {
            steps {
                sh '''
                    echo "Checking Prometheus is up and scraping Jenkins..."
                    STATUS=$(curl -s http://petclinic-prometheus:9090/api/v1/targets | python3 -c "import sys,json; targets=json.load(sys.stdin)['data']['activeTargets']; jenkins=[t for t in targets if t['labels'].get('job')=='jenkins']; print(jenkins[0]['health'] if jenkins else 'not found')")
                    echo "Jenkins target status in Prometheus: $STATUS"
                    if [ "$STATUS" != "up" ]; then
                        echo "WARNING: Prometheus is not scraping Jenkins metrics."
                    else
                        echo "Monitoring OK - Grafana dashboard available at http://petclinic-grafana:3000"
                    fi
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