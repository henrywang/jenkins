def API_PORT = '8989'
def HYPERVISOR = 3

pipeline {
    agent none
    stages {
        stage('Provision') {
            agent {
                node {
                    label '3rd-CIBUS'
                    customWorkspace "workspace/pipeline-${env.BUILD_ID}"
                }
            }
            steps {
                echo 'Setup server ...'
                script {
                    API_PORT = sh(returnStdout: true, script: 'awk -v min=1025 -v max=9999 \'BEGIN{srand(); print int(min+rand()*(max-min+1))}\'')
                }
                echo "API Port: ${API_PORT}"
                sh 'printenv'
                cleanWs()
            }
        }
        stage('Hypervisor Setup') {
            environment {
                HV = "${HYPERVISOR}"
            }
            parallel {
                stage('Hyper-V') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-hyperv-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'hyper-v'
                        cleanWs()
                    }
                }
                stage('ESXi') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-esxi-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '2' || HV == '3'}
                    }
                    steps {
                        echo 'esxi'
                        cleanWs()
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