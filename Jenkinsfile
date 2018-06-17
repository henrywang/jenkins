def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}
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
        release = '902.el7.test'
        id = '16710241'
        owner = 'xiaofwan'
        RHEL_VER = sh(returnStdout: true, script: "[[ $version = 4.* ]] && echo '8' || echo '7'").trim()
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
                NFS_IP = credentials('nfs-ip')
                NFS_PATH = credentials('nfs-path')
            }
            steps {
                echo 'Running Omni Container...'
                sh """
                    sudo docker network inspect jenkins >/dev/null 2>&1 || sudo docker network create jenkins
                    sudo docker pull henrywangxf/jenkins:latest
                    sudo docker ps --quiet --all --filter 'name=omni-${API_PORT}' | sudo xargs --no-run-if-empty docker rm -f
                    sudo docker volume ls --quiet --filter 'name=kernels-volume-${API_PORT}' | sudo xargs --no-run-if-empty docker volume rm
                    sudo docker volume inspect nfs > /dev/null 2>&1 || \
                        sudo docker volume create --driver local \
                        --opt type=nfs --opt o=addr=${NFS_IP} --opt device=:${NFS_PATH} nfs
	                sudo docker run -d --name omni-${API_PORT} --restart=always \
                        -p ${API_PORT}:22 -v kernels-volume-${API_PORT}:/kernels -v nfs:/kernels/nfs \
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
        stage('Hypervisor Test Matrix') {
            environment {
                DOMAIN = credentials('hyperv-domain-login')
                OMNI_IP = credentials('omni-server-ip')
                OMNI_USER = credentials('omni-scp-username')
            }
            parallel {
                stage('Smoking Test - Hyper-V 2016 Gen1') {
                    // options {
                    //     timeout(time: 2, unit: 'HOURS')
                    // }
                    environment {
                        HOST_ID = '2016-AUTO'
                        IMAGE = "image-2016-${RHEL_VER}.vhdx"
                    }
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-2016-g1-smoking-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'Checkout VM Provision Code'
                        checkout scm
                        echo 'Gen1 VM Provision on 2016'
                        powershell 'Get-ChildItem Env:'
                        RunPowershellCommand(".\\runner.ps1 -action add")
                        echo 'Checkout LISA Code'
                        checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'lis']], submoduleCfg: [], userRemoteConfigs: [[url: 'https://github.com/LIS/lis-test.git']]]
                        RunPowershellCommand(".\\runner.ps1 -action run")
                    }
                    post {
                        always {
                            // Delete VM(s)
                            RunPowershellCommand(".\\runner.ps1 -action del")
                            // Upload result to omni server
                            RunPowershellCommand(".\\runner.ps1 -action put")
                            // Publish jnunt test result report
                            junit allowEmptyResults: true, testResults: 'report*.xml'
                            // Archive log files
                            archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/**/*.*'
                            // Clear workspace
                            cleanWs()
                        }
                    }
                }
                stage('Smoking Test - Hyper-V 2012R2 Gen2') {
                    // options {
                    //     timeout(time: 2, unit: 'HOURS')
                    // }
                    environment {
                        HOST_ID = '2012R2-AUTO'
                        IMAGE = "image-2012r2-${RHEL_VER}.vhdx"
                    }
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-2012r2-g2-smoking-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'Checkout VM Provision Code'
                        checkout scm
                        echo 'Gen2 VM Provision on 2012R2'
                        RunPowershellCommand(".\\runner.ps1 -action add -gen2")
                        echo 'Checkout LISA Code'
                        checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'lis']], submoduleCfg: [], userRemoteConfigs: [[url: 'https://github.com/LIS/lis-test.git']]]
                        RunPowershellCommand(".\\runner.ps1 -action run -gen2")
                    }
                    post {
                        always {
                            // Delete VM(s)
                            RunPowershellCommand(".\\runner.ps1 -action del -gen2")
                            // Upload result to omni server
                            RunPowershellCommand(".\\runner.ps1 -action put -gen2")
                            // Publish jnunt test result report
                            junit allowEmptyResults: true, testResults: 'report*.xml'
                            // Archive log files
                            archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/**/*.*'
                            // Clear workspace
                            cleanWs()
                        }
                    }
                }
                stage('Smoking Test - Hyper-V 2012 Gen1') {
                    // options {
                    //     timeout(time: 2, unit: 'HOURS')
                    // }
                    environment {
                        HOST_ID = '2012-72-132'
                        IMAGE = "image-2012-${RHEL_VER}.vhdx"
                    }
                    agent {
                        node {
                            label '3rd-CIVAN'
                            customWorkspace "workspace/pipeline-2012-g1-smoking-${env.BUILD_ID}"
                        }
                    }
                    when {
                        expression { HV == '1' || HV == '3'}
                    }
                    steps {
                        echo 'Checkout VM Provision Code'
                        checkout scm
                        echo 'Gen1 VM Provision on 2012'
                        RunPowershellCommand(".\\runner.ps1 -action add")
                        echo 'Checkout LISA Code'
                        checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'lis']], submoduleCfg: [], userRemoteConfigs: [[url: 'https://github.com/LIS/lis-test.git']]]
                        RunPowershellCommand(".\\runner.ps1 -action run")
                    }
                    post {
                        always {
                            // Delete VM(s)
                            RunPowershellCommand(".\\runner.ps1 -action del")
                            // Upload result to omni server
                            RunPowershellCommand(".\\runner.ps1 -action put")
                            // Publish jnunt test result report
                            junit allowEmptyResults: true, testResults: 'report*.xml'
                            // Archive log files
                            archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/**/*.*'
                            // Clear workspace
                            cleanWs()
                        }
                    }
                }
                stage('Functional Test - Hyper-V 2016 Gen2') {
                    // options {
                    //     timeout(time: 6, unit: 'HOURS')
                    // }
                    environment {
                        HOST_ID = '2016-AUTO'
                        IMAGE = "image-2016-${RHEL_VER}.vhdx"
                    }
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
                        echo 'Checkout VM Provision Code'
                        checkout scm
                        echo 'Gen2 VM Provision on 2016'
                        powershell 'Get-ChildItem Env:'
                        RunPowershellCommand(".\\runner.ps1 -action add -dual -gen2")
                        echo 'Checkout LISA Code'
                        checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'lis']], submoduleCfg: [], userRemoteConfigs: [[url: 'https://github.com/LIS/lis-test.git']]]
                        RunPowershellCommand(".\\runner.ps1 -action run -dual -gen2")
                    }
                    post {
                        always {
                            // Delete VM(s)
                            RunPowershellCommand(".\\runner.ps1 -action del -dual -gen2")
                            // Upload result to omni server
                            RunPowershellCommand(".\\runner.ps1 -action put -dual -gen2")
                            // Publish jnunt test result report
                            junit allowEmptyResults: true, testResults: 'report*.xml'
                            // Archive log files
                            archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/**/*.*'
                            // Clear workspace
                            cleanWs()
                        }
                    }
                }
                stage('Functional Test - Hyper-V 2012R2 Gen1') {
                    // options {
                    //     timeout(time: 6, unit: 'HOURS')
                    // }
                    environment {
                        HOST_ID = '2012R2-AUTO'
                        IMAGE = "image-2012r2-${RHEL_VER}.vhdx"
                    }
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
                        echo 'Checkout VM Provision Code'
                        checkout scm
                        echo 'Gen1 VM Provision on 2012R2'
                        RunPowershellCommand(".\\runner.ps1 -action add -dual")
                        echo 'Checkout LISA Code'
                        checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'lis']], submoduleCfg: [], userRemoteConfigs: [[url: 'https://github.com/LIS/lis-test.git']]]
                        RunPowershellCommand(".\\runner.ps1 -action run -dual")
                    }
                    post {
                        always {
                            // Delete VM(s)
                            RunPowershellCommand(".\\runner.ps1 -action del -dual")
                            // Upload result to omni server
                            RunPowershellCommand(".\\runner.ps1 -action put -dual")
                            // Publish jnunt test result report
                            junit allowEmptyResults: true, testResults: 'report*.xml'
                            // Archive log files
                            archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/**/*.*'
                            // Clear workspace
                            cleanWs()
                        }
                    }
                }
                stage('Functional Test - Hyper-V 2012 Gen1') {
                    // options {
                    //     timeout(time: 6, unit: 'HOURS')
                    // }
                    environment {
                        HOST_ID = '2012-72-132'
                        IMAGE = "image-2012-${RHEL_VER}.vhdx"
                    }
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
                        echo 'Checkout VM Provision Code'
                        checkout scm
                        echo 'Gen1 VM Provision on 2012'
                        RunPowershellCommand(".\\runner.ps1 -action add -dual")
                        echo 'Checkout LISA Code'
                        checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'lis']], submoduleCfg: [], userRemoteConfigs: [[url: 'https://github.com/LIS/lis-test.git']]]
                        RunPowershellCommand(".\\runner.ps1 -action run -dual")
                    }
                    post {
                        always {
                            // Delete VM(s)
                            RunPowershellCommand(".\\runner.ps1 -action del -dual")
                            // Upload result to omni server
                            RunPowershellCommand(".\\runner.ps1 -action put -dual")
                            // Publish jnunt test result report
                            junit allowEmptyResults: true, testResults: 'report*.xml'
                            // Archive log files
                            archiveArtifacts allowEmptyArchive: true, artifacts: 'TestResults/**/*.*'
                            // Clear workspace
                            cleanWs()
                        }
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

                sudo docker volume ls --quiet --filter 'name=nfs' | sudo xargs --no-run-if-empty docker volume rm
                sudo docker rmi -f henrywangxf/jenkins:latest
            """
            // sudo docker volume ls --quiet --filter 'name=kernels-volume-${API_PORT}' | sudo xargs --no-run-if-empty docker volume rm
            cleanWs()
        }
    }
    options {
        skipDefaultCheckout()
        timestamps()
        buildDiscarder(logRotator(numToKeepStr:'10'))
        // timeout(time: 6, unit: 'HOURS')
    }
}