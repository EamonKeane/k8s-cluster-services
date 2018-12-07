#!/usr/bin/groovy
pipeline {
  agent {
    kubernetes {
      label 'jenkins-open-source-helm'
      yamlFile 'jenkinsPodTemplate.yml'
    }
  }
  stages {
    stage('Checkout code') {
      steps {
        container('jnlp'){
          script{
            inputFile = readFile('Jenkinsfile.json')
            config = new groovy.json.JsonSlurperClassic().parseText(inputFile)
            containerTag = env.BRANCH_NAME + '-' + env.GIT_COMMIT.substring(0, 7)
            println "pipeline config ==> ${config}"
          } // script
        } // container('jnlp')
      } // steps
    } // stage
    stage('Initialise Helm Jenkins'){
      steps {
        container('gcloud-helm'){
          sh "helm repo add ${config.helm.opensourceRepo.repoName} ${config.helm.opensourceRepo.repo}"
          //push cluster svc
          sh "helm push ${config.helm.clusterSvcFolder}/ ${config.helm.opensourceRepo.repoName}"
          //push jenkins
          sh "helm push ${config.helm.jenkinsFolder}/ ${config.helm.opensourceRepo.repoName}"
        }//container gcloud-helm
      }//steps
    }//stage 
  } // stages
} // pipeline
