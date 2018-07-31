# Deploy common tools in a k8s cluster

## To Do

* Install starfish
* Install squareroute
* Install Cluster Autoscaler

## Setting up helm

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

* Get credentials from Google dashboard (CLIENT_ID, CLIENT_SECRET)

```bash
helm dependency update kibana-ingress
```

```bash
helm upgrade \
    --install \
    --namespace $CHART_NAMESPACE \
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