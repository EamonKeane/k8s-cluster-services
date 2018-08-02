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

* My domain: `airflow-develop.squareroute.io`

* Create the oauth2 secret on Google with the following configuration:

* Navigate to https://console.cloud.google.com/apis/credentials?project=$PROJECT
* Click Create Credentials
* Select OAuth Client ID
* Select Web Application
* Enter $OAUTH_APP_NAME as the Name
* In authorized redirect URLs, enter https://$MY_DOMAIN/oauth2callback

Click download json at the top of the page.

```bash
MY_OAUTH2_CREDENTIALS=/Users/Eamon/Downloads/client_secret_937018571230-ncri1j04vkd23q19hfc9rpu73k2u9fck.apps.googleusercontent.com.json
CLIENT_ID=$(jq .web.client_id $MY_OAUTH2_CREDENTIALS --raw-output )
CLIENT_SECRET=$(jq .web.client_secret $MY_OAUTH2_CREDENTIALS --raw-output )
kubectl create secret generic google-oauth \
        --namespace airflow \
        --from-literal=client_id=$CLIENT_ID \
        --from-literal=client_secret=$CLIENT_SECRET
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
RELEASE_NAME=cluster-svc
CHART_NAMESPACE=cluster-svc
GRAFANA_CONFIGMAP=$RELEASE_NAME-grafana
echo "%s#http://$RELEASE_NAME:9090#http://$RELEASE_NAME-prometheus:9090#g" | tr -d '\n' | pbcopy
kubectl edit cm $GRAFANA_CONFIGMAP --namespace $CHART_NAMESPACE
```

Press the `:` key to get into `vim` command mode and `CMD + v` to paste.

Press `esc` and `wq` to save and exit.

Delete the grafana pod to restart it.

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
* Ensure the callback url is of the form `${url}/oauth2/callback` for the form oauth2_proxy expects

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

For subsequent upgrades to reuse values:

```bash
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    --reuse-values \
    kibana-ingress \
    kibana-ingress
```

```bash
helm dependency update grafana-ingress
```

```bash
MY_OAUTH2_CREDENTIALS=/Users/Eamon/Downloads/client_secret_937018571230-u3v37s6rvigonaf7nhgn0usdrk029rt1.apps.googleusercontent.com.json
CLIENT_ID=$(jq .web.client_id $MY_OAUTH2_CREDENTIALS --raw-output )
CLIENT_SECRET=$(jq .web.client_secret $MY_OAUTH2_CREDENTIALS --raw-output )
COOKIE_SECRET=$(python -c 'import os,base64; print base64.urlsafe_b64encode(os.urandom(16))')
```

```bash
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
    --set oauth2-proxy.config.clientID=$CLIENT_ID \
    --set oauth2-proxy.config.clientSecret=$CLIENT_SECRET \
    --set oauth2-proxy.config.cookieSecret=$COOKIE_SECRET \
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
MY_OAUTH2_CREDENTIALS=/Users/Eamon/Downloads/client_secret_937018571230-imha6arufc1radnv9vnsv9jo4vfguslu.apps.googleusercontent.com.json
CLIENT_ID=$(jq .web.client_id $MY_OAUTH2_CREDENTIALS --raw-output )
CLIENT_SECRET=$(jq .web.client_secret $MY_OAUTH2_CREDENTIALS --raw-output )
COOKIE_SECRET=$(python -c 'import os,base64; print base64.urlsafe_b64encode(os.urandom(16))')
```

```bash
helm upgrade \
    --install \
    --namespace cluster-svc \
    --set oauth2-proxy.config.clientID=$CLIENT_ID \
    --set oauth2-proxy.config.clientSecret=$CLIENT_SECRET \
    --set oauth2-proxy.config.cookieSecret=$COOKIE_SECRET \
    jenkins \
    jenkins-oauth \
    --debug \
    --dry-run >> test-output.yaml
```

Without oauth:

```bash
helm upgrade \
    --install \
    --namespace cluster-svc \
    jenkins \
    jenkins
```

Install the secret in the namespace for pull secrets.

```bash
SECRET_NAME=logistio-deploy-pull-secret
NAMESPACE=default
DOCKER_USERNAME=logistio-deploy
DOCKER_PASSWORD=
DOCKER_SERVER=quay.io/logistio
kubectl create secret docker-registry $SECRET_NAME \
        --namespace $NAMESPACE \
        --docker-username=$DOCKER_USERNAME \
        --docker-password=$DOCKER_PASSWORD \
        --docker-email="" \
        --docker-server=$DOCKER_SERVER

NAMESPACE=default
SERVICE_ACCOUNT=default
kubectl patch serviceaccount --namespace $NAMESPACE $SERVICE_ACCOUNT \
  -p "{\"imagePullSecrets\": [{\"name\": \"$SECRET_NAME\"}]}"
```

Add the logistio-deploy-quay-password

```bash
cat <<EOF | kubectl create -f -
apiVersion: v1
data:
  docker_password:
  <GET FROM LASTPASS>
kind: Secret
metadata:
  name: logistio-deploy-quay-password
  namespace: cluster-svc
type: Opaque
EOF
```

Create the azure connection secret

```bash
cat <<EOF | kubectl create -f -
apiVersion: v1
data:
  connection_string: <GET FROM LASTPASS>
kind: Secret
metadata:
  name: az-fileshare-connection-string
  namespace: cluster-svc
type: Opaque
EOF
```

Create the kubeconfig secrets for develop and production.

```bash
NAMESPACE=cluster-svc
CLUSTER_NAME=squareroute-develop
RESOURCE_GROUP=squareroute-develop
TEMP_DIRECTORY=$PWD
KUBECONFIG_FILE_OUTPUT=$PWD/kubeconfig
az aks get-credentials \
  --name $CLUSTER_NAME \
  --admin \
  --resource-group $RESOURCE_GROUP \
  --file $KUBECONFIG_FILE_OUTPUT

SECRET_NAME=develop-cluster-kubeconfig
kubectl create secret generic $SECRET_NAME \
    --namespace $NAMESPACE \
    --from-file=$KUBECONFIG_FILE_OUTPUT
```

## Install just prometheus+grafana

```bash
helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
helm install coreos/prometheus-operator --name prometheus-operator --namespace $CHART_NAMESPACE
helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring
```

SSH to azure node. <https://docs.microsoft.com/en-us/azure/aks/aks-ssh>

```bash
VM_USERNAME=azureuser
NODE_NAME=aks-nodepool1-47278868-0
CONTAINER_LIFETIME=600
INTERNAL_IP=$(kubectl get nodes --selector=kubernetes.io/hostname=$NODE_NAME -o json | jq .items[0].status.addresses[0].address --raw-output)
DEPLOYMENT_NAME=aksssh
LABELS="app=aksssh"
kubectl run $POD_NAME --image=debian --labels=$LABELS --command sleep $CONTAINER_LIFETIME
sleep 60
POD_NAME=$(kubectl get po --selector=$LABELS -o json | jq .items[0].metadata.name --raw-output)
kubectl exec $POD_NAME -- apt-get update
kubectl exec $POD_NAME -- apt-get install openssh-client -y
kubectl cp ~/.ssh/id_rsa $POD_NAME:/id_rsa
kubectl exec $POD_NAME -- chmod 0600 id_rsa
kubectl exec -it $POD_NAME -- ssh -i id_rsa $VM_USERNAME@$INTERNAL_IP
# Say yes to accept commands
# Run commands on VM node
# Exit
# Delete the deployment
kubectl delete deploy --selector=$LABELS
```