master_ip=$1
echo $master_ip
echo 'export VERIFY_CHECKSUM=false' >> /root/.bashrc

source /root/.bashrc

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3

chmod 700 get_helm.sh

HELM_INSTALL_DIR=/usr/bin ./get_helm.sh



kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo update 

helm upgrade --namespace monitoring --install kube-stack-prometheus prometheus-community/kube-prometheus-stack --set prometheus-node-exporter.hostRootFsMount.enabled=false

sleep 60

kubectl port-forward --namespace monitoring svc/kube-stack-prometheus-kube-prometheus 9090:9090 --address=0.0.0.0 &

kubectl port-forward -n portworx svc/grafana 3000:3000 --address=0.0.0.0 &

sleep 30

curl -X POST http://admin:admin@$master_ip:3000/api/datasources \
    -H "Content-Type: application/json" \
    -d '{"name":"Prometheus", "type":"prometheus", "url":"http://'"$master_ip"':9090/", "access":"proxy", "basicAuth":false}'


