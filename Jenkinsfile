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
  hostPathVolume(mountPath: "/home/jenkins/.draft", hostPath: "/home/jenkins/.draft"),
  hostPathVolume(mountPath: "/home/jenkins/.helm", hostPath: "/home/jenkins/.helm")
]) {
  node(label) {
    stage("Checkout") {
      if (env.REPOSITORY_SECRET) {
        git(url: "$REPOSITORY_URL", branch: "$BRANCH", credentialsId: "$REPOSITORY_SECRET")
      } else {
        git(url: "$REPOSITORY_URL", branch: "$BRANCH")
      }
    }
    stage("Make Version") {
      container("builder") {
        sh """
          bash /root/extra/jenkins-domain.sh
          bash /root/extra/jenkins-version.sh $IMAGE_NAME $BRANCH
        """
      }
    }
    stage("Make Charts") {
      container("builder") {
        def BASE_DOMAIN = readFile "/home/jenkins/BASE_DOMAIN"
        def REGISTRY = readFile "/home/jenkins/REGISTRY"
        def VERSION = readFile "/home/jenkins/VERSION"
        sh """
          # Chart.yaml
          sed -i -e "s/name: .*/name: $IMAGE_NAME/" charts/acme/Chart.yaml
          sed -i -e "s/version: .*/version: $VERSION/" charts/acme/Chart.yaml
          cat charts/acme/Chart.yaml
          # values.yaml
          sed -i -e "s|basedomain: .*|basedomain: $BASE_DOMAIN|" charts/acme/values.yaml
          sed -i -e "s|repository: .*|repository: $REGISTRY/$IMAGE_NAME|" charts/acme/values.yaml
          sed -i -e "s|tag: .*|tag: $VERSION|" charts/acme/values.yaml
          cat charts/acme/values.yaml
          # mv
          mv charts/acme charts/$IMAGE_NAME
        """
      }
    }
    if (BRANCH != 'master') {
      stage("Deploy Development") {
        container("builder") {
          def NAMESPACE = "development"
          sh """
            bash /root/extra/draft-init.sh
            sed -i -e "s/NAMESPACE/$NAMESPACE/g" draft.toml
            sed -i -e "s/NAME/$IMAGE_NAME-$NAMESPACE/g" draft.toml
            cat draft.toml
            draft up --docker-debug
          """
        }
      }
    }
    if (BRANCH == 'master') {
      stage("Build Image") {
        container("docker") {
          def REGISTRY = readFile "/home/jenkins/REGISTRY"
          def VERSION = readFile "/home/jenkins/VERSION"
          sh """
            docker build -t $REGISTRY/$IMAGE_NAME:$VERSION .
            docker push $REGISTRY/$IMAGE_NAME:$VERSION
          """
        }
      }
      stage("Build Charts") {
        container("builder") {
          def BASE_DOMAIN = readFile "/home/jenkins/BASE_DOMAIN"
          def REGISTRY = readFile "/home/jenkins/REGISTRY"
          def VERSION = readFile "/home/jenkins/VERSION"
          sh """
            bash /root/extra/helm-init.sh
            cd charts/$IMAGE_NAME
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
    }
  }
}
