#!/usr/bin/groovy
pipeline {
  agent {
    kubernetes {
      label 'jenkins-insights-data-py'
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
    stage('Initialise Helm Jenkins Squareroute'){
      when {
          expression { config.buildBranch.contains(env.BRANCH_NAME) }
      }
      steps {
        container('gcloud-helm'){
          sh "helm repo add opensource-helm ${config.helm.repository}"
          sh "helm push ${config.helm.helm-folder}/ ${config.helm.repository-name}"
        }//container gcloud-helm
      }//steps
    }//stage 
  } // stages
} // pipeline
