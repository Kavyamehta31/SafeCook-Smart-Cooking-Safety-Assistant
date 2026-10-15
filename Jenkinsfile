
pipeline {
    agent any

    options {
        timestamps()
    }

    stages {
        stage('Check Environment') {
            steps {
                bat 'java -version'
                bat 'git --version'
                bat 'flutter --version'
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
                bat 'flutter build apk --debug'
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
    }
}
