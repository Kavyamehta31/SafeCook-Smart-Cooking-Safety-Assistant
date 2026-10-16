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
                bat 'flutter test --reporter expanded > functional-test-report.txt 2>&1'
            }
        }

        stage('Non-Functional Testing') {
        steps {
            bat '''
                 @echo off
                echo SafeCook Non-Functional Test Report > non-functional-report.txt
                echo =================================== >> non-functional-report.txt
                echo. >> non-functional-report.txt
                 echo Test start time: %DATE% %TIME% >> non-functional-report.txt

                set START=%TIME%
                flutter test --reporter expanded > reliability-test-output.txt 2>&1
                if errorlevel 1 goto test_failed

                echo Reliability test result: PASSED >> non-functional-report.txt
                echo All automated tests passed on the repeated run. >> non-functional-report.txt
                echo. >> non-functional-report.txt
                echo Limitations: This is a repeatability check, not a load or memory test. >> non-functional-report.txt
                    goto test_done

                    :test_failed
                echo Reliability test result: FAILED >> non-functional-report.txt
                type reliability-test-output.txt
                exit /b 1

                :test_done
                echo Test completion time: %DATE% %TIME% >> non-functional-report.txt
                echo Detailed output: reliability-test-output.txt >> non-functional-report.txt
            '''
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
            echo 'SafeCook functional and non-functional pipeline checks completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check Console Output and archived test reports.'
        }
    }
}
