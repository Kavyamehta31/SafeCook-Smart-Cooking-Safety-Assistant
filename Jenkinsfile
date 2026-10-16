pipeline {
    agent any

    options {
        timestamps()
    }

    environment {
        FLUTTER_HOME = 'C:\\Development\\flutter'
        ANDROID_HOME = 'C:\\Users\\dell\\AppData\\Local\\Android\\Sdk'
        PATH = "${FLUTTER_HOME}\\bin;${ANDROID_HOME}\\platform-tools;${ANDROID_HOME}\\cmdline-tools\\latest\\bin;${env.PATH}"
    }

    stages {
        stage('Check Environment') {
            steps {
                bat 'java -version'
                bat 'git --version'
                bat 'flutter --version'
                bat 'node --version'
                bat 'npm --version'
                bat 'flutter doctor'
            }
        }

        stage('Install Flutter Dependencies') {
            steps {
                bat 'flutter pub get'
            }
        }

        stage('Install Backend Dependencies') {
            steps {
                dir('safecook-search-backend') {
                    bat 'npm ci'
                }
            }
        }

        stage('Static Code Analysis') {
            steps {
                bat 'flutter analyze'
            }
        }

        stage('Flutter Functional Testing') {
            steps {
                script {
                    int result = bat(
                        returnStatus: true,
                        script: 'flutter test --reporter expanded > functional-test-report.txt 2>&1'
                    )

                    if (result != 0) {
                        bat 'type functional-test-report.txt'
                        error('Flutter functional tests failed.')
                    }

                    echo 'Flutter functional tests passed.'
                }
            }
        }

        stage('Backend Functional Testing') {
            steps {
                dir('safecook-search-backend') {
                    script {
                        int result = bat(
                            returnStatus: true,
                            script: 'npm test -- --run > backend-test-report.txt 2>&1'
                        )

                        if (result != 0) {
                            bat 'type backend-test-report.txt'
                            error('Backend functional tests failed.')
                        }

                        echo 'Backend functional tests passed.'
                    }
                }
            }
        }

        stage('Non-Functional Testing') {
            steps {
                dir('safecook-search-backend') {
                    script {
                        def startTime = System.currentTimeMillis()

                        int result = bat(
                            returnStatus: true,
                            script: 'npm test -- --run -t "Non-Functional Checks" > nfr-test-output.txt 2>&1'
                        )

                        def endTime = System.currentTimeMillis()
                        def duration = (endTime - startTime) / 1000.0

                        def report = """SafeCook Non-Functional Test Report
===================================
Test category: Backend response time and repeatability
Start time: ${new Date(startTime)}
End time: ${new Date(endTime)}
NFR test suite duration: ${duration} seconds
NFR test command exit code: ${result}
NFR test result: ${result == 0 ? 'PASSED' : 'FAILED'}

The test measures mocked local worker response time and repeated invalid-request handling.
It does not measure live Tavily latency, production load, or mobile-device memory usage.

Detailed output: safecook-search-backend/nfr-test-output.txt
"""

                        writeFile(
                            file: 'non-functional-report.txt',
                            text: report
                        )

                        if (result != 0) {
                            bat 'type nfr-test-output.txt'
                            error('Backend NFR tests failed.')
                        }

                        echo "NFR suite duration: ${duration} seconds"
                    }
                }
            }
        }

        stage('Build Android APK') {
            steps {
                bat 'flutter build apk --debug'
            }
        }
    }

    post {
        always {
            archiveArtifacts(
                artifacts: 'build/app/outputs/flutter-apk/*.apk, functional-test-report.txt, non-functional-report.txt, safecook-search-backend/backend-test-report.txt, safecook-search-backend/nfr-test-output.txt',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'SafeCook FR and NFR pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check Console Output and archived reports.'
        }
    }
}
