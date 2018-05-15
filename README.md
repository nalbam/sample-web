# sample-web
```
FROM httpd:latest
EXPOSE 80

docker pull nalbam/sample-web:latest (69MB)
docker pull nalbam/sample-web:alpine (28MB)
```

## Openshift
### Create project
```
oc new-project ops
oc new-project dev
oc new-project qa

oc policy add-role-to-user admin admin -n ops
oc policy add-role-to-user admin admin -n dev
oc policy add-role-to-user admin admin -n qa
```

### Create app
```
oc new-app -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/deploy.json -n dev
oc new-app -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/deploy.json -n qa
```

### Create pipeline
```
oc new-app jenkins-ephemeral -n ops

oc new-app -f https://raw.githubusercontent.com/nalbam/sample-web/master/openshift/templates/pipeline.json -n ops \
           -p SOURCE_REPOSITORY_URL=https://github.com/nalbam/sample-web

oc policy add-role-to-user edit system:serviceaccount:ops:jenkins -n dev
oc policy add-role-to-user edit system:serviceaccount:ops:jenkins -n qa

oc policy add-role-to-group system:image-puller system:serviceaccounts:ops -n dev
oc policy add-role-to-group system:image-puller system:serviceaccounts:ops -n qa
```

### Start Build
```
oc start-build sample-web-pipeline -n ops
```

### Cleanup
```
oc delete project ops dev qa
```
