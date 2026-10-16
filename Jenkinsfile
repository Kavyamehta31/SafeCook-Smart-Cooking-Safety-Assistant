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
                bat 'flutter doctor'
            }
        }

        stage('Install Dependencies') {
            steps {
                bat 'flutter pub get'
            }
        }

        stage('Static Code Analysis') {
            steps {
                bat 'flutter analyze'
            }
        }

        stage('Functional Testing') {
            steps {
                script {
                    int testResult = bat(
                        returnStatus: true,
                        script: 'flutter test --reporter expanded > functional-test-report.txt 2>&1'
                    )

                    if (testResult != 0) {
                        bat 'type functional-test-report.txt'
                        error('Functional tests failed. Check functional-test-report.txt.')
                    }

                    echo 'Functional tests passed.'
                }
            }
        }

        stage('Non-Functional Testing') {
            steps {
                script {
                    def startTime = System.currentTimeMillis()

                    int testResult = bat(
                        returnStatus: true,
                        script: 'flutter test --reporter expanded > reliability-test-output.txt 2>&1'
                    )

                    def endTime = System.currentTimeMillis()
                    def durationSeconds = (endTime - startTime) / 1000.0

                    def report = """SafeCook Non-Functional Test Report
===================================
Test type: Repeatability / reliability check
Start time: ${new Date(startTime)}
End time: ${new Date(endTime)}
Execution duration: ${durationSeconds} seconds
Test command exit code: ${testResult}
Reliability test result: ${testResult == 0 ? 'PASSED' : 'FAILED'}

Note: This check repeats the Flutter automated test suite.
It does not measure real-device load, memory usage, or backend response time.
Detailed output: reliability-test-output.txt
"""

                    writeFile(
                        file: 'non-functional-report.txt',
                        text: report
                    )

                    echo "Repeated test execution duration: ${durationSeconds} seconds"

                    if (testResult != 0) {
                        bat 'type reliability-test-output.txt'
                        error('Reliability tests failed. Check reliability-test-output.txt.')
                    }

                    echo 'Non-functional repeatability check passed.'
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
                artifacts: 'build/app/outputs/flutter-apk/*.apk, functional-test-report.txt, non-functional-report.txt, reliability-test-output.txt',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'SafeCook functional and non-functional checks completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check Console Output and archived reports.'
        }
    }
}
