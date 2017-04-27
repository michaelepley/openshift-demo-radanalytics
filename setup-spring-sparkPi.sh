#!/bin/bash

# See http://radanalytics.io/applications/spring_sparkpi
# and https://github.com/radanalyticsio/spring-sparkpi

echo "Create a RadAnalytics example application: Spring-SparkPi"
echo "	--> make sure we are logged in"
oc whoami || oc login master.rhsademo.net -u mepley -p ${OPENSHIFT_RHSADEMO_USER_PASSWORD_DEFAULT}

echo "	--> checking for prerequisites RadAnalytics resources"
oc get dc/oshinko || { echo "FAILED: missing Rad Analytics resources -- run setup to recreate" && exit 1 ; }
oc project rad-analytics || { echo "FAILED: missing project -- run setup to recreate" && exit 1 ; }
oc get service/oshinko-web || { echo "WARNING: missing web frontend for RadAnalytics, you will not be able to control the Spark cluster through the GUI"; }
[ `oc get limits --template='{{range $obj, $objs := (index .items 0).spec.limits }}{{if (eq .type "Container")}}{{.min.cpu}}{{end}}{{end}}' | grep -oP '\d*(\.\d*)?'` -gt 10 ] || { echo "FAILED: insufficient CPU limits available, contact your system administrator" && exit 1; }
[ `oc get limits --template='{{range $obj, $objs := (index .items 0).spec.limits }}{{if (eq .type "Pod")}}{{.max.cpu}}{{end}}{{end}}' | grep -oP '\d*(\.\d*)?'` -lt 1000 ] || { echo "FAILED: insufficient CPU limits available, contact your system administrator" && exit 1; }
[ `oc get limits --template='{{range $obj, $objs := (index .items 0).spec.limits }}{{if (eq .type "Pod")}}{{.max.memory}}{{end}}{{end}}' | grep -oP '\d*(\.\d*)?'` -le 2 ] || { echo "FAILED: insufficient memory limits available, contact your system administrator" && exit 1; }

echo "	--> Create the necessary image streams"
oc get is radanalyticsio/radanalytics-java-spark || oc get is radanalyticsio/radanalytics-java-spark -n openshift || oc import-image radanalyticsio/radanalytics-java-spark --confirm || { echo "FAILED: Could not create image stream radanalyticsio/radanalytics-java-spark" && exit 1; } 

echo "	--> Create the example application"
# need OSHINKO_CLUSTER_NAME ?
oc new-app --template oshinko-java-spark-build-dc -p APPLICATION_NAME=spring-sparkpi -p GIT_URI=https://github.com/radanalyticsio/spring-sparkpi -p APP_FILE=SparkPiBoot-0.0.1-SNAPSHOT.jar
# make sure the build configuration has sufficient memory to complete the build process
{ oc get bc/spring-sparkpi && oc cancel-build bc/spring-sparkpi ; } || { echo "FAILED: could not cancel build" && exit 1 ; }
oc patch bc/spring-sparkpi -p '{ "spec" : {  "resources" : { "requests" : { "cpu" : "900m" , "memory" : "1000Mi" } , "limits" : { "cpu" : "1000m" , "memory" : "1500Mi" } } } }' || { echo "FAILED: could not patch build configuration to ensure sufficient build resources" && exit 1 ; }
oc patch dc/spring-sparkpi -p '{"spec" : { "template" : { "spec" : { "containers" : [ { "name" : "spring-sparkpi", "resources" : { "requests" : { "cpu" : "400m" , "memory" : "1000Mi" } , "limits" : { "cpu" : "1000m" , "memory" : "1500Mi" } } } ] } } } }'
oc patch dc/spring-sparkpi -p '{"spec" : { "template" : { "spec" : { "containers" : [ { "name" : "spring-sparkpi", "resources" : { "requests" : { "cpu" : "400m" } } } ] } } } }'
oc start-build spring-sparkpi
echo "	--> Wait the sample application to be ready"
sleep 10;
echo "	--> Expose the sample application"
oc expose svc/spring-sparkpi
OPENSHIFT_DEMO_RADANALYTICS_SAMPLE_APPLICATION_SPRING_SPARKPI_ROUTE=`oc get routes/spring-sparkpi --template='{{.spec.host}}'`

echo "	--> Validate the sample applicaton"
curl http://${OPENSHIFT_DEMO_RADANALYTICS_SAMPLE_APPLICATION_SPRING_SPARKPI_ROUTE}

echo "	-->	To use the application, go to curl http://${OPENSHIFT_DEMO_RADANALYTICS_SAMPLE_APPLICATION_SPRING_SPARKPI_ROUTE}"

echo "	--> To clean up, use: oc delete all -l app=spring-sparkpi"
echo "Done."


