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
                    mkdir -p burp
                    rm -f burp/burp-report.html burp/burp-report.xml burp/scan.log burp/burp-session.log

                                        # Set BURP_TARGET_URL in Jenkins job/environment as needed.
                                        # Example: http://192.168.56.10:8080
                    : "${BURP_TARGET_URL:=http://192.168.56.10:8080}"
                                        : "${BURP_SCAN_MODE:=manual}"

                    set +e
                                        docker network inspect petclinic-devops-net >/dev/null 2>&1 || docker network create petclinic-devops-net

                                        # Start Burp Community container as the assignment requires.
                                        docker compose -f burp/docker-compose.burp.yml up -d --build > burp/burp-session.log 2>&1
                                        COMPOSE_EXIT=$?

                                        # Optional short wait for UI readiness (best effort)
                                        sleep 8
                                        curl -fsS http://localhost:6081 >/dev/null 2>&1
                                        READY_EXIT=$?

                    # Burp Community scanning is interactive.
                    # Generate a deterministic report each build so Jenkins never
                    # republishes stale output from previous runs.
                    cat > burp/burp-report.html <<EOF
<html>
    <head><title>Burp Community Scan Report</title></head>
    <body>
        <h1>Burp Community Scan Report</h1>
        <p>Burp Community container started from pipeline.</p>
        <p>Target URL: ${BURP_TARGET_URL}</p>
        <p>Scan mode: ${BURP_SCAN_MODE}</p>
        <p>Container startup exit code: ${COMPOSE_EXIT}</p>
        <p>UI readiness check exit code: ${READY_EXIT}</p>
        <p>If a manual scan was performed, replace this file with exported Burp HTML report.</p>
        <p>See archived logs: burp/scan.log and burp/burp-session.log</p>
    </body>
</html>
EOF

                    cat > burp/burp-report.xml <<EOF
<burpScan>
    <status>community</status>
    <mode>${BURP_SCAN_MODE}</mode>
    <target>${BURP_TARGET_URL}</target>
    <composeExit>${COMPOSE_EXIT}</composeExit>
    <uiReadyExit>${READY_EXIT}</uiReadyExit>
</burpScan>
EOF

                    {
                        echo "Burp Community stage summary"
                        echo "BURP_TARGET_URL=${BURP_TARGET_URL}"
                        echo "BURP_SCAN_MODE=${BURP_SCAN_MODE}"
                        echo "COMPOSE_EXIT=${COMPOSE_EXIT}"
                        echo "READY_EXIT=${READY_EXIT}"
                    } > burp/scan.log

                    echo "========== Burp HTML Report =========="
                    cat burp/burp-report.html
                    echo "========== Burp XML Report =========="
                    cat burp/burp-report.xml
                    echo "========== Burp Scan Log =========="
                    cat burp/scan.log

                    # Leave non-blocking for demo pipelines.
                    # If desired, make blocking by failing on COMPOSE_EXIT/READY_EXIT.
                    docker compose -f burp/docker-compose.burp.yml down >/dev/null 2>&1 || true
                    set -e
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
                    reportName: 'Burp Community Report'
                ])
                archiveArtifacts artifacts: 'burp/burp-report.*,burp/scan.log,burp/burp-session.log', allowEmptyArchive: true
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