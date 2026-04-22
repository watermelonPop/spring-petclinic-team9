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
                    rm -f burp/burp-report.html burp/burp-report.xml burp/scan.log burp/burp-config.runtime.yml

                    # Set BURP_TARGET_URL in Jenkins job/environment as needed.
                    # Example: http://192.168.56.10:8080
                    : "${BURP_TARGET_URL:=http://192.168.56.10:8080}"
                    : "${BURP_SCANNER_IMAGE:=public.ecr.aws/portswigger/ci-scanner:latest}"

                    sed "s|http://TARGET_URL_PLACEHOLDER|${BURP_TARGET_URL}|g" \
                        burp/burp-config.yml > burp/burp-config.runtime.yml

                    set +e
                    docker run --rm \
                        --network petclinic-devops-net \
                        -v "$PWD/burp:/burp" \
                        "$BURP_SCANNER_IMAGE" \
                        --config-file=/burp/burp-config.runtime.yml > burp/scan.log 2>&1
                    SCAN_EXIT=$?
                    set -e

                    if [ ! -f burp/burp-report.html ]; then
                        cat > burp/burp-report.html <<EOF
<html>
  <head><title>Burp Scan Report (Fallback)</title></head>
  <body>
    <h1>Burp Scan Report (Fallback)</h1>
    <p>Burp scanner did not generate an HTML report file.</p>
    <p>Target URL: ${BURP_TARGET_URL}</p>
    <p>Scanner image: ${BURP_SCANNER_IMAGE}</p>
    <p>Scanner exit code: ${SCAN_EXIT}</p>
    <p>See archived artifact: burp/scan.log</p>
  </body>
</html>
EOF
                    fi

                    if [ ! -f burp/burp-report.xml ]; then
                        cat > burp/burp-report.xml <<EOF
<burpScan>
  <status>fallback</status>
  <target>${BURP_TARGET_URL}</target>
  <scannerImage>${BURP_SCANNER_IMAGE}</scannerImage>
  <exitCode>${SCAN_EXIT}</exitCode>
</burpScan>
EOF
                    fi

                    if [ ${SCAN_EXIT} -ne 0 ]; then
                        echo "Burp scanner exited with code ${SCAN_EXIT}. Fallback report generated; check burp/scan.log"
                    fi
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
                archiveArtifacts artifacts: 'burp/burp-report.*,burp/scan.log', allowEmptyArchive: true
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