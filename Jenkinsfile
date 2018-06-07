pipeline {
    agent none
    environment {
        HYPERVISOR = 0
        API_PORT = 8989
    }
    stages {
        stage('Provision') {
            agent {
                label '3rd-CIBUS'
            }
            steps {
                echo 'Setup server ...'
                script {
                    API_PORT = Math.abs(new Random().nextInt() % 9999 + 1024)
                }
                sh 'echo $API_PORT'
            }
        }
        stage('Hypervisor Setup') {
            parallel {
                stage('Hyper-V') {
                    when {
                        anyof {
                            environment name: 'HYPERVISOR', value: 1
                            environment name: 'HYPERVISOR', value: 4
                        }
                    }
                }
                stage('ESXi') {
                    when {
                        anyof {
                            environment name: 'HYPERVISOR', value: 2
                            environment name: 'HYPERVISOR', value: 4
                        }
                    }
                }
            }
        }
        stage('Clean Up') {

        }
    }
}