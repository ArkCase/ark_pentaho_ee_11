# Pentaho Enterprise Edition for Arkcase

Pentaho is business intelligence (BI) software that provides data integration, OLAP services, reporting, information dashboards, data mining and extract, transform, load (ETL) capabilities.

Pentaho Documentation is available at https://www.hitachivantara.com/en-us/products/dataops-software/data-integration-analytics/download-pentaho.html

## How to build:

./get-artifacts.sh

cd ../artifacts_ark_pentaho_ee

python3 -m http.server 8000

note: modify BUILD_SERVER in ./Dockerfile to match ip address where artifacts are being hosted

docker build -t ark_pentaho_ee:latest .

Repository pushes occur automatically when code is checked in.

## How to run: (Helm) 

helm repo add arkcase https://arkcase.github.io/ark_helm_charts/

helm install ark-pentaho-ee arkcase/ark-pentaho-ee

helm uninstall ark-pentaho-ee

## How to run: (Kubernetes)

kubectl create -f pod_ark_pentaho_ee.yaml

Look around shell

kubectl exec -it pod/ark-pentaho -- bash

Web browser to http://server:8080/

kubectl --namespace default port-forward pod/ark-pentaho-ee 2002 8080:8080 --address='0.0.0.0'

kubectl delete -f pod_ark_pentaho_ee.yaml

## How to run: (Docker)

docker run --name ark_pentaho_ee -d 345280441424.dkr.ecr.ap-south-1.amazonaws.com/ark_pentaho_ee:latest

docker exec -it ark_pentaho_ee /bin/bash

docker stop ark_pentaho_ee

docker rm ark_pentaho_ee
