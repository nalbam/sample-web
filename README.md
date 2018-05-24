# sample-web

## Docker
```bash
docker pull nalbam/sample-web:latest # 69MB
docker pull nalbam/sample-web:alpine # 28MB
```

## Openshift

### Create Project
```bash
oc new-project ops
oc new-project dev
oc new-project qa

oc policy add-role-to-user admin admin -n ops
oc policy add-role-to-user admin admin -n dev
oc policy add-role-to-user admin admin -n qa
```

### Create Catalog
```bash
oc create -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/deploy.json \
          -n ops

oc create -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/pipeline.json \
          -n ops
```

### Create Application
```bash
oc new-app -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/deploy.json -n dev
oc new-app -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/deploy.json -n qa
```

### Create Pipeline
```bash
oc new-app jenkins-ephemeral -n ops

oc policy add-role-to-user edit system:serviceaccount:ops:jenkins -n dev
oc policy add-role-to-user edit system:serviceaccount:ops:jenkins -n qa

oc new-app -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/pipeline.json \
           -p SOURCE_REPOSITORY_URL=https://github.com/nalbam/sample-web \
           -p JENKINS_URL=https://jenkins-ops.apps.nalbam.com \
           -p SLACK_WEBHOOK_URL=https://hooks.slack.com/services/web/hook/token \
           -n ops
```

### Start Build
```bash
oc start-build sample-web-pipeline -n ops
```

### Cleanup
```bash
oc delete project ops dev qa
```
