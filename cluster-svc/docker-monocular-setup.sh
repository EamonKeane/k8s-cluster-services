helm install monocular/monocular \
    --name monocular -f /Users/Eamon/kubernetes/k8s-cluster-services/cluster-svc/monocular-values.yaml

kubectl create secret generic monocular-basic-auth --from-file=auth

DOCKER_PASSWORD_FILE=secrets/docker-password
DOCKER_USERNAME_FILE=secrets/docker-username 
DOCKER_USERNAME=docker
DOCKER_REGISTRY=https://docker-registry-test.squareroute.io
echo ${DOCKER_USERNAME} > ${DOCKER_USERNAME_FILE}
openssl rand -base64 500 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 > ${DOCKER_PASSWORD_FILE}
# had to use B to force bcrypt on mac
htpasswd -Bbn docker $(cat $DOCKER_PASSWORD_FILE)

helm upgrade \
    --install \
    docker-registry \
    stable/docker-registry \
    --values cluster-svc/docker-registry.yaml \
    --set secrets.htpasswd=$(htpasswd -Bbn docker $(cat ${DOCKER_PASSWORD_FILE}))

docker login --password $(cat ${DOCKER_PASSWORD_FILE}) \
             --username $(cat ${DOCKER_USERNAME_FILE}) \
             ${DOCKER_REGISTRY}


helm upgrade \
     --install \
     --set tags.bare-metal=true \
     cluster-svc \
     cluster-svc \
     --debug \
     --dry-run > test-output.yaml

kubectl --namespace kube-system create serviceaccount tiller || true
kubectl create clusterrolebinding tiller \
                --clusterrole cluster-admin \
                --serviceaccount=kube-system:tiller || true
helm init --wait --service-account tiller

NAMESPACE=cluster-svc

helm upgrade \
     --install \
     --set tags.cicd=true \
     cluster-svc \
     cluster-svc \
     --namespace ${NAMESPACE} \
     --values cluster-svc/over-rides.yaml \
     --debug \
     --dry-run > test-output.yaml

helm del --purge cluster-svc
kubectl delete ns cluster-svc
kubectl delete apiservice v1beta1.metrics.k8s.io
kubectl delete crd certificates.certmanager.k8s.io
kubectl delete crd clusterissuers.certmanager.k8s.io
kubectl delete crd issuers.certmanager.k8s.io