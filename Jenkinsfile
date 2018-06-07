pipeline {
    agent none
    environment {
        HYPERVISOR = '4'
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
                        anyOf {
                            environment name: 'HYPERVISOR', value: '1'
                            environment name: 'HYPERVISOR', value: '4'
                        }
                    }
                    steps {
                        echo 'hyper-v'
                    }
                }
                stage('ESXi') {
                    when {
                        anyOf {
                            environment name: 'HYPERVISOR', value: '2'
                            environment name: 'HYPERVISOR', value: '4'
                        }
                    }
                    steps {
                        echo 'esxi'
                    }
                }
            }
        }
        stage('Clean Up') {
            steps {
                echo 'clean up'
            }
        }
    }
}