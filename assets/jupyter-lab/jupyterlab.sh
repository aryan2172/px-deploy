kubectl patch storageclass px-db -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl create namespace jlab
chmod 777 /assets/jupyter-lab

kubectl apply -f /assets/jupyter-lab/jupyterlab-pvc.yaml
kubectl apply -f /assets/jupyter-lab/jupyterlab-deployment.yaml
kubectl apply -f /assets/jupyter-lab/jupyterlab-service.yaml

kubectl port-forward --namespace jlab svc/jupyterlab 80 --address=0.0.0.0
