#!/bin/bash

# See https://docs.openshift.com/enterprise/latest for general openshift docs
# See http://radanalytics.io/get-started

echo "Create a RadAnalytics environment"
echo "	--> make sure we are logged in"
oc whoami || oc login master.rhsademo.net -u mepley -p ${OPENSHIFT_RHSADEMO_USER_PASSWORD_DEFAULT}

echo "	--> Create build for the required base images"
echo "		--> importing base image(s)"
oc get is fedora:25 || oc get is fedora:25 -n openshift || oc import-image fedora:25 --confirm || { echo "FAILED: could not find or create required image" && exit 1 ; }
oc get is centos || oc get is centos -n openshift || oc import-image centos --confirm || { echo "FAILED: could not find or create required image" && exit 1 ; }

echo "		--> creating the base image for spark components"
oc get bc/openshift-spark || oc new-build --name="openshift-spark" --image-stream="fedora:25" --code="https://github.com/radanalyticsio/openshift-spark.git" --strategy=docker --context-dir="." --to=openshift-spark || { echo "FAILED: could not create build for base spark component" && exit 1 ; } 

echo "		--> creating the spark java components"
if [ ! `oc get bc/radanalytics-java-spark` ]; then 
	oc new-build --name="radanalytics-java-spark" --image-stream="fedora:25" --code="https://github.com/radanalyticsio/oshinko-s2i.git" --strategy=docker --dockerfile="Dockerfile.java" --context-dir="." --to=radanalytics-java-spark || { echo "WARNING: could not create build for java spark component" ; } 
	oc cancel-build bc/radanalytics-java-spark
	oc patch bc/radanalytics-java-spark -p '{"spec" : { "strategy" : { "dockerStrategy" : { "dockerfilePath" : "java" } } } }'
	oc start-build bc/radanalytics-java-spark
fi 
echo "		--> creating the spark python components"
if [ ! `oc get bc/radanalytics-pyspark` ]; then 
	oc new-build --name="radanalytics-pyspark" --image-stream="fedora:25" --code="https://github.com/radanalyticsio/oshinko-s2i.git" --strategy=docker --dockerfile="Dockerfile.pyspark" --context-dir="." --to=radanalytics-pyspark || { echo "WARNING: could not create build for python spark component" ; }
	oc cancel-build bc/radanalytics-pyspark
	oc patch bc/radanalytics-pyspark -p '{"spec" : { "strategy" : { "dockerStrategy" : { "dockerfilePath" : "pyspark" } } } }'
	oc start-build bc/radanalytics-pyspark
fi
echo "		--> creating the spark scala components"
if [ ! `oc get bc/radanalytics-scala` ]; then 
	oc new-build --name="radanalytics-scala" --image-stream="fedora:25" --code="https://github.com/radanalyticsio/oshinko-s2i.git" --strategy=docker --dockerfile="Dockerfile.scala" --context-dir="." --to=radanalytics-scala || { echo "WARNING: could not create build for spark scala component" ; }
	oc cancel-build bc/radanalytics-scala
	oc patch bc/radanalytics-scala -p '{"spec" : { "strategy" : { "dockerStrategy" : { "dockerfilePath" : "scala" } } } }'
	oc start-build bc/radanalytics-scala
fi

echo "	--> create a project for our work"
oc project rad-analytics || oc new-project rad-analytics || { echo "FAILED: could not create project" && exit 1 ; }

echo "		--> create the oshinko service account that will be used to interact with openshift to manage spark clusters"
oc get sa/oshinko || oc create serviceaccount oshinko
echo "		--> add the necessary role bindings to the oshinko service account"
# oc adm policy add-role-to-user edit system:serviceaccount:oshinko
oc adm policy add-role-to-user edit --serviceaccount=oshinko
# Note: the base fedora image does not include nodejs and npm; we need to install these first in a temporary image
oc new-build --name=fedora-nodejs --image-stream=fedora:25 --dockerfile=$'FROM fedora:25\nRUN dnf -y install nodejs npm' --strategy=docker 
# Note: the original container to deploy was 'radanalyticsio/oshinko-webui', but we are replacing this with an image built in openshift
# Note: the original OSHINKO_SPARK_IMAGE was 'radanalyticsio/openshift-spark' , we are replacing this with one managed as an image stream in openshift 'openshift-spark'
oc new-app --name=oshinko-web fedora-nodejs~https://github.com/radanalyticsio/oshinko-webui.git --strategy=docker -e OSHINKO_SPARK_IMAGE=openshift-spark -e OSHINKO_REFRESH_INTERVAL=5
oc expose dc oshinko-web 
# oc set probe dc/oshinko --readiness --get-url=http://:8080/
# oc set probe dc/oshinko --liveness --get-url=http://:8080/



# OR use prebuilt template__________
# echo "	--> create the prerequisite RadAnalytics resources"
# curl -sSKL http://radanalytics.io/resources.yaml -o oshinko-resources.yaml
# oc get dc/oshinko || oc create -f http://radanalytics.io/resources.yaml || { echo "FAILED: could not create Rad Analytics resources" && exit 1 ; }
# echo "	--> create the front-end web app"
# oc get service/oshinko-web || oc new-app oshinko-webui -l app=radanalyics -l part=frontend ||  { echo "FAILED: could not create web frontend for RadAnalytics" && exit 1 ; }
# __________

echo "	--> to clean: oc delete all -l build=fedora-nodejs && oc delete all -l app=oshinko-web "

echo "Done."