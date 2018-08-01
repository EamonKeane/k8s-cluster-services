# Deploy common tools in a k8s cluster

## To Do

* Install starfish
* Install squareroute
* Install Cluster Autoscaler

## Setting up Cluster

```bash
git clone https://github.com/EamonKeane/airflow-GKE-k8sExecutor-helm
cd airflow-GKE-k8sExecutor-helm

RESOURCE_GROUP=squareroute-develop
LOCATION=westeurope
STORAGE_ACCOUNT_NAME=squareroutedevairflow
POSTGRES_DATABASE_INSTANCE_NAME=squareroute-develop-airflow
NODE_VM_SIZE=Standard_DS14_v2
NODE_COUNT=2
AIRFLOW_NAMESPACE=airflow
./aks-sql-k8s-install.sh \
  --resource-group=$RESOURCE_GROUP \
  --location=$LOCATION \
  --storage-account-name=$STORAGE_ACCOUNT_NAME \
  --postgres-database-instance-name=$POSTGRES_DATABASE_INSTANCE_NAME \
  --node-vm-size=$NODE_VM_SIZE \
  --node-count=$NODE_COUNT \
  --airflow-namespace=$AIRFLOW_NAMESPACE
```

* In airflow/azure-airflow-values.yaml, change `STORAGE_ACCOUNT_NAME` to the above:

```bash
sed -i "" -e "s/storageAccountName:.*/storageAccountName: ${STORAGE_ACCOUNT_NAME}/" airflow/azure-airflow-values.yaml
sed -i "" -e "s/namespace:.*/namespace: ${AIRFLOW_NAMESPACE}/" airflow/azure-airflow-values.yaml
sed -i "" -e "s/location:.*/location: ${LOCATION}/" airflow/azure-airflow-values.yaml
```

Copy and paste the below into the context of the root of the airflow repo.

```bash
VALUES_FILE_ROOT_PATH=/Users/Eamon/kubernetes/k8s-cluster-services
VALUES_FILE_RELATIVE_PATH=airflow/azure-airflow-values.yaml
VALUES_FILE_FULL_PATH=$VALUES_FILE_ROOT_PATH/$VALUES_FILE_RELATIVE_PATH
helm upgrade \
    --install \
    --namespace $AIRFLOW_NAMESPACE \
    --values $VALUES_FILE_FULL_PATH \
    airflow \
    airflow
```

## Azure Cluster Permissions

* The newly created cluster must be given access to the VNET and the ability to make resources in the cluster (such as a load balancer). The `clientId` can be gotten by the below:

```bash
CLUSTER_NAME=my-cluster
RESOURCE_GROUP=my-resource-group
az aks show \
    --name ${CLUSTER_NAME} \
    --resource-group ${RESOURCE_GROUP} -o json \
    | jq .servicePrincipalProfile.clientId --raw-output \
    | pbcopy
```

* Go to the dashboard, select the managed cluster in resource groups, this will be of the form:

```bash
"MC_${CLUSTER_NAME}_${RESOURCE_GROUP}_${LOCATION}"
```

* Select `Access Control`, select `+Add`, select role `owner`, in the `Select` box (third one down), paste in the `ClientId`. Click on the resulting username (e.g. it will appear as `theifberyl-cluster`), press `Save`.

* Delete the `nginx-ingress` svc and re-install. LoadBalancer IP wil be provisioned in around 4 minutes.

## Setting up Helm and master services chart

Add the following repos to your local helm client.

```bash
helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
helm repo add stable http://kubernetes-charts.storage.googleapis.com/
```

Run helm dependency update to download 8 charts to `cluster-svc/charts` directory

```bash
helm dependency update cluster-svc
```

It is necessary to install `coreos/prometheus-operator` first because the error below appears otherwise (<https://github.com/helm/helm/issues/2994>).

```bash
Error: apiVersion "monitoring.coreos.com/v1" in ... .yaml is not available
```

Install the chart. (note ignore warnings `warning: skipped value for env: Not a table.` from kibana as this still formats correctly).

```bash
CHART_NAMESPACE=cluster-svc
helm install coreos/prometheus-operator --name prometheus-operator --namespace $CHART_NAMESPACE
```

For Azure and for GKE 1.11+, use the below.

```bash
FOLDER_NAME=cluster-svc
RELEASE_NAME=cluster-svc
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    $RELEASE_NAME \
    $FOLDER_NAME
```

For GKE below 1.10 use the below(<https://github.com/coreos/prometheus-operator/blob/master/contrib/kube-prometheus/docs/GKE-cadvisor-support.md>). Some screens still do not appear to work.

```bash
FOLDER_NAME=cluster-svc
RELEASE_NAME=cluster-svc
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    --set kube-prometheus.exporter-kubelets.https=False \
    $RELEASE_NAME \
    $FOLDER_NAME
```


Edit the grafana configmap to put in the correct prometheus name. This is because the values in `k8s-cluster-services/cluster-svc/charts/kube-prometheus/charts/grafana/templates/dashboards-configmap.yaml:L27` contains `.Release.Name` which defaults to `cluster-svc`. The actual prometheus service produced by the chart is `cluster-svc-prometheus`.

```yaml
  prometheus-datasource.json: |+
    {
      "access": "proxy",
      "basicAuth": false,
      "name": "prometheus",
      "type": "prometheus",
      "url": "http://{{ printf "%s" .Release.Name }}:9090"
    }
```

Edit the grafana configmap:

```bash
GRAFANA_CONFIGMAP=$RELEASE_NAME-grafana
echo "%s#http://$RELEASE_NAME:9090#http://$RELEASE_NAME-prometheus:9090#g" | tr -d '\n' | pbcopy
kubectl edit cm $GRAFANA_CONFIGMAP --namespace $CHART_NAMESPACE
```

Press the `:` key to get into `vim` command mode and `CMD + v` to paste.

Press `esc` and `wq` to save and exit.

## Kibana log setup

```bash
export KIBANA_POD_NAME=$(kubectl get pods --namespace $CHART_NAMESPACE -l "app=kibana" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $KIBANA_POD_NAME 5601:5601
```

* Click on `Management` on left hand side
* Click on `Index Patterns`
* Enter `logstash-*` as log patern
* Enter `@Timestamp` as the index.
* Logs should now be visible in the `Discover` tab

## Cert-manager cluster-issuer

Create the cluster-issuer for acme:

```bash
cat <<EOF | kubectl create -f -
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: mydomain@logistio.ie
    privateKeySecretRef:
      name: letsencrypt-prod
    http01: {}
EOF
```

## Install SSL ingress for kibana and grafana

* Get credentials from Google dashboard (CLIENT_ID, CLIENT_SECRET).

```bash
MY_OAUTH2_CREDENTIALS=/Users/Eamon/Downloads/client_secret_937018571230-233dtulm06to6sh9vt1115s0oeqb1ba7.apps.googleusercontent.com.json
CLIENT_ID=$(jq .web.client_id $MY_OAUTH2_CREDENTIALS --raw-output )
CLIENT_SECRET=$(jq .web.client_secret $MY_OAUTH2_CREDENTIALS --raw-output )
COOKIE_SECRET=$(python -c 'import os,base64; print base64.urlsafe_b64encode(os.urandom(16))')
```

```bash
helm dependency update kibana-ingress
```

```bash
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    --set oauth2-proxy.config.clientID=$CLIENT_ID \
    --set oauth2-proxy.config.clientSecret=$CLIENT_SECRET \
    --set oauth2-proxy.config.cookieSecret=$COOKIE_SECRET \
    kibana-ingress \
    kibana-ingress
```

```bash
helm dependency update grafana-ingress
```

```bash
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    grafana-ingress \
    grafana-ingress
```

## Debug

To debug the chart, enter the following:

```bash
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    $RELEASE_NAME \
    $FOLDER_NAME \
    --debug \
    --dry-run \
    >> test-output.yaml
```

## Tidy up

Delete the chart and the statefulset elasticsearch.

```bash
helm del --purge $RELEASE_NAME
kubectl delete statefulset.apps/cluster-svc-elasticsearch-data --namespace $CHART_NAMESPACE
kubectl delete service/alertmanager-operated --namespace $CHART_NAMESPACE
kubectl delete service/prometheus-operated --namespace $CHART_NAMESPACE
```

## Install jenkins

```bash
helm upgrade \
    --install \
    --namespace cluster-svc \
    jenkins \
    jenkins
```

## Install just prometheus+grafana

```bash
helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
helm install coreos/prometheus-operator --name prometheus-operator --namespace $CHART_NAMESPACE
helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring
```