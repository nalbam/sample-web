def label = "worker-${UUID.randomUUID().toString()}"
properties([
  buildDiscarder(logRotator(daysToKeepStr: "60", numToKeepStr: "30"))
])
podTemplate(label: label,
containers: [
  containerTemplate(name: "builder", image: "quay.io/nalbam/builder", command: "cat", ttyEnabled: true),
  containerTemplate(name: "docker", image: "docker", command: "cat", ttyEnabled: true)
],
volumes: [
  hostPathVolume(mountPath: "/var/run/docker.sock", hostPath: "/var/run/docker.sock"),
  hostPathVolume(mountPath: "/home/jenkins/.version", hostPath: "/home/jenkins/.version"),
  hostPathVolume(mountPath: "/home/jenkins/.helm", hostPath: "/home/jenkins/.helm")
]) {
  node(label) {
    stage("Checkout") {
      git(url: "$REPOSITORY_URL", branch: "$BRANCH")
    }
    if (BRANCH != 'master') {
      stage("Deploy Development") {
        container("builder") {
          def NAMESPACE = "development"
          sh """
            sed -i -e "s/name: .*/name: \"$IMAGE_NAME\"" draft.toml
            sed -i -e "s/namespace: .*/namespace: \"$NAMESPACE\"" draft.toml
            draft up
          """
        }
      }
    }
    if (BRANCH == 'master') {
      stage("Make Version") {
        container("builder") {
          sh """
            bash /root/extra/jenkins-domain.sh
            bash /root/extra/jenkins-version.sh $IMAGE_NAME $BRANCH
          """
        }
      }
      stage("Image Build") {
        container("docker") {
          def REGISTRY = readFile "/home/jenkins/REGISTRY"
          def VERSION = readFile "/home/jenkins/VERSION"
          sh """
            docker build -t $REGISTRY/$IMAGE_NAME:$VERSION .
            docker push $REGISTRY/$IMAGE_NAME:$VERSION
          """
        }
      }
      stage("Chart Build") {
        container("builder") {
          def BASE_DOMAIN = readFile "/home/jenkins/BASE_DOMAIN"
          def REGISTRY = readFile "/home/jenkins/REGISTRY"
          def VERSION = readFile "/home/jenkins/VERSION"
          sh """
            bash /root/extra/helm-init.sh
            mv charts/acme charts/$IMAGE_NAME
            cd charts/$IMAGE_NAME
            sed -i -e "s/name: .*/name: $IMAGE_NAME/" Chart.yaml
            sed -i -e "s/version: .*/version: $VERSION/" Chart.yaml
            sed -i -e "s|basedomain: .*|basedomain: $BASE_DOMAIN|" values.yaml
            sed -i -e "s|repository: .*|repository: $REGISTRY/$IMAGE_NAME|" values.yaml
            sed -i -e "s|tag: .*|tag: $VERSION|" values.yaml
            helm lint .
            helm push . chartmuseum
            helm repo update
            helm search $IMAGE_NAME
          """
        }
      }
      stage("Deploy Staging") {
        container("builder") {
          def NAMESPACE = "staging"
          def VERSION = readFile "/home/jenkins/VERSION"
          sh """
            helm upgrade --install $IMAGE_NAME-$NAMESPACE chartmuseum/$IMAGE_NAME \
                        --version $VERSION --namespace $NAMESPACE --devel \
                        --set fullnameOverride=$IMAGE_NAME-$NAMESPACE
            helm history $IMAGE_NAME-$NAMESPACE
          """
        }
      }
      stage("Proceed Production") {
        container("builder") {
          def VERSION = readFile "/home/jenkins/VERSION"
          def JENKINS = readFile "/home/jenkins/JENKINS"
          def URL = "https://$JENKINS/blue/organizations/jenkins/$env.JOB_NAME/detail/$env.JOB_NAME/$env.BUILD_NUMBER/pipeline"
          timeout(time: 30, unit: "MINUTES") {
            input(message: "Proceed Production?: $IMAGE_NAME-$VERSION")
          }
        }
      }
      stage("Deploy Production") {
        container("builder") {
          def NAMESPACE = "production"
          def VERSION = readFile "/home/jenkins/VERSION"
          sh """
            helm upgrade --install $IMAGE_NAME-$NAMESPACE chartmuseum/$IMAGE_NAME \
                        --version $VERSION --namespace $NAMESPACE --devel \
                        --set fullnameOverride=$IMAGE_NAME-$NAMESPACE
            helm history $IMAGE_NAME-$NAMESPACE
          """
        }
      }
    }
  }
}
