
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

        stage('Flutter Analysis') {
            steps {
                bat 'flutter analyze'
            }
        }

        stage('Automated Tests') {
            steps {
                bat 'flutter test --reporter expanded'
            }
        }

        stage('Build Android APK') {
            steps {
                bat 'flutter build apk --debug -v'
            }
        }
    }

    post {
        always {
            archiveArtifacts(
                artifacts: 'build/app/outputs/flutter-apk/*.apk',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'SafeCook pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check Console Output.'
        }
    }
}
