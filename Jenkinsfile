pipeline {
    agent {
        node {
            label '3rd-CIBUS'
            customWorkspace "workspace/pipeline-${env.BUILD_ID}"
        }
    }
    environment {
        name = 'kernel'
        version = '3.10.0'
        release = '900.el7.test'
        id = '16636204'
        API_PORT = sh(returnStdout: true, script: 'awk -v min=1025 -v max=9999 \'BEGIN{srand(); print int(min+rand()*(max-min+1))}\'').trim()
        HV = sh(returnStdout: true, script: """
                if [[ $release = *"hyperv"* ]] || [[ $release = *"hyper-v"* ]] || [[ $release = *"hyper"* ]]; then 
                    echo "1"
                elif [[ $release = *"esxi"* ]] || [[ $release = *"esx"* ]]; then
                    echo "2"
                else
                    echo "3"
                fi
                """).trim()
    }
    stages {
        stage('Omni Server Provision') {
            environment {
                PUBLIC_KEY = credentials('3rd_id_rsa_pub')
            }
            steps {
                echo 'Running Omni Container...'
                sh """
                    sudo docker network inspect jenkins >/dev/null 2>&1 || sudo docker network create jenkins
                    sudo docker pull henrywangxf/jenkins:latest
                    sudo docker ps --quiet --all --filter 'name=omni-${API_PORT}' | sudo xargs --no-run-if-empty docker rm -f
                    sudo docker volume ls --quiet --filter 'name=kernels-volume-${API_PORT}' | sudo xargs --no-run-if-empty docker volume rm
	                sudo docker run -d --name omni-${API_PORT} --restart=always \
                        -p ${API_PORT}:22 -v kernels-volume-${API_PORT}:/kernels \
                        --network jenkins --security-opt label=disable \
                        -e AUTHORIZED_KEYS=\"${PUBLIC_KEY}\" \
                        henrywangxf/jenkins:latest
                """
                sh 'printenv'
                cleanWs()
            }
        }
        stage('Kernel Download') {
            environment {
                BREW_API = credentials('3rd-brew-api-address')
            }
            steps {
                echo 'Downloading kernel rpm...'
                sh """
                    sudo docker ps --quiet --all --filter 'name=download-${API_PORT}' | sudo xargs --no-run-if-empty docker rm -f
	                sudo docker run --rm --name download-${API_PORT} \
                        -v kernels-volume-${API_PORT}:/kernels --network jenkins \
                        henrywangxf/jenkins:latest \
                        python3 kbot.py ${name}-${version}-${release} ${BREW_API} --download --id ${id} --path /kernels
                """
                echo "API_PORT: ${API_PORT}"
                cleanWs()
            }
        }
        stage('Hypervisor Matrix') {
            parallel {
                stage('Hyper-V 2016 Gen2') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-2016-g2-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'Gen2 VM Provision on 2016'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
                stage('Hyper-V 2012R2 Gen1') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-2012r2-g1-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'Gen1 VM Provision on 2012R2'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
                stage('Hyper-V 2012 Gen1') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-2012-g1-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'Gen1 VM Provision on 2012'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
                stage('ESXi 6.7 EFI') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-6.7-efi-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '2' || HV == '3'}
                    }
                    steps {
                        echo 'EFI VM Provision on ESXi 6.7'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
                stage('ESXi 6.5 BIOS') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-6.5-bios-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '2' || HV == '3'}
                    }
                    steps {
                        echo 'BIOS VM Provision on ESXi 6.5'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
                stage('ESXi 6.0 EFI') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-6.0-efi-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '2' || HV == '3'}
                    }
                    steps {
                        echo 'EFI VM Provision on ESXi 6.0'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
                stage('ESXi 5.5 BIOS') {
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-5.5-bios-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '2' || HV == '3'}
                    }
                    steps {
                        echo 'BIOS VM Provision on ESXi 5.5'
                        echo 'Test Running'
                        cleanWs()
                    }
                }
            }
        }
    }
    post {
        always {
            echo 'Stop and remove omni container'
            echo 'Start result analyzer and email sender container'
            echo 'Remove volume'
            sh """
                sudo docker ps --quiet --all --filter 'name=omni-${API_PORT}' | sudo xargs --no-run-if-empty docker rm -f
                sudo docker volume ls --quiet --filter 'name=kernels-volume-${API_PORT}' | sudo xargs --no-run-if-empty docker volume rm
            """
            cleanWs()
        }
    }
    options {
        skipDefaultCheckout()
        timestamps()
        buildDiscarder(logRotator(numToKeepStr:'10'))
        timeout(time: 6, unit: 'HOURS')
    }
}