
user=$1
namespace=$2

kubectl patch storageclass px-db -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash

mv kustomize /bin/


cd /assets/manifests

sed -i "s/user@example.com/$user/g" /assets/manifests/common/dex/base/config-map.yaml

sed -i "s/user@example.com/$user/g" /assets/manifests/common/user-namespace/base/param.env

sed -i "s/kubeflow-user-example-com/$namespace/g" /assets/manifests/common/user-namespace/base/param.env

while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
