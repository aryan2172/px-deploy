set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew

echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /root/.bashrc
echo 'export VERIFY_CHECKSUM=false' >> /root/.bashrc
source /root/.bashrc

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
HELM_INSTALL_DIR=/usr/bin ./get_helm.sh

cd /assets/hlf-operator

#INSTALL ISTIO
kubectl apply -f ./hack/istio-operator/crds/*
helm template ./hack/istio-operator/ \
  --set hub=docker.io/istio \
  --set tag=1.8.0 \
  --set operatorNamespace=istio-operator \
  --set watchedNamespaces=istio-system | kubectl apply -f -

kubectl create ns istio-system
kubectl apply -n istio-system -f ./hack/istio-operator.yaml

helm repo add kfs https://kfsoftware.github.io/hlf-helm-charts --force-update
helm install hlf-operator --version=1.6.0 kfs/hlf-operator

kubectl krew install hlf
#kubectl krew upgrade hlf 


export PEER_IMAGE=hyperledger/fabric-peer
export PEER_VERSION=2.4.3

export ORDERER_IMAGE=hyperledger/fabric-orderer
export ORDERER_VERSION=2.4.3


#Deploying a Certificate Authority
kubectl hlf ca create --storage-class=px-db --capacity=2Gi --name=org1-ca \
    --enroll-id=enroll --enroll-pw=enrollpw
kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all

# register user for the peers
kubectl hlf ca register --name=org1-ca --user=peer --secret=peerpw --type=peer \
 --enroll-id enroll --enroll-secret=enrollpw --mspid Org1MSP

#Deploying a peer

kubectl hlf peer create --statedb=couchdb --image=$PEER_IMAGE --version=$PEER_VERSION --storage-class=px-db --enroll-id=peer --mspid=Org1MSP \
        --enroll-pw=peerpw --capacity=5Gi --name=org1-peer0 --ca-name=org1-ca.default
kubectl wait --timeout=180s --for=condition=Running fabricpeers.hlf.kungfusoftware.es --all

#Deploying an Ordering Service
#Deploying a certificate authority
kubectl hlf ca create --storage-class=px-db --capacity=2Gi --name=ord-ca \
    --enroll-id=enroll --enroll-pw=enrollpw
kubectl wait --timeout=180s --for=condition=Running fabriccas.hlf.kungfusoftware.es --all
kubectl hlf ca register --name=ord-ca --user=orderer --secret=ordererpw \
    --type=orderer --enroll-id enroll --enroll-secret=enrollpw --mspid=OrdererMSP

#Deploying the Orderer nodes node
kubectl hlf ordnode create --image=$ORDERER_IMAGE --version=$ORDERER_VERSION \
    --storage-class=px-db --enroll-id=orderer --mspid=OrdererMSP \
    --enroll-pw=ordererpw --capacity=2Gi --name=ord-node1 --ca-name=ord-ca.default
kubectl wait --timeout=180s --for=condition=Running fabricorderernodes.hlf.kungfusoftware.es --all


#Preparing a connection string for the ordering service
kubectl hlf inspect --output ordservice.yaml -o OrdererMSP
kubectl hlf ca register --name=ord-ca --user=admin --secret=adminpw \
    --type=admin --enroll-id enroll --enroll-secret=enrollpw --mspid=OrdererMSP

kubectl hlf ca enroll --name=ord-ca --user=admin --secret=adminpw --mspid OrdererMSP \
        --ca-name ca  --output admin-ordservice.yaml
## add user from admin-ordservice.yaml to ordservice.yaml
kubectl hlf utils adduser --userPath=admin-ordservice.yaml --config=ordservice.yaml --username=admin --mspid=OrdererMSP


#Create a channel
kubectl hlf channel generate --output=demo.block --name=demo --organizations Org1MSP --ordererOrganizations OrdererMSP

# enroll using the TLS CA
kubectl hlf ca enroll --name=ord-ca --namespace=default --user=admin --secret=adminpw --mspid OrdererMSP \
        --ca-name tlsca  --output admin-tls-ordservice.yaml

kubectl hlf ordnode join --block=demo.block --name=ord-node1 --namespace=default --identity=admin-tls-ordservice.yaml


#Preparing a connection string for the peer
kubectl hlf ca register --name=org1-ca --user=admin --secret=adminpw --type=admin \
 --enroll-id enroll --enroll-secret=enrollpw --mspid Org1MSP

kubectl hlf ca enroll --name=org1-ca --user=admin --secret=adminpw --mspid Org1MSP \
        --ca-name ca  --output peer-org1.yaml

kubectl hlf inspect --output org1.yaml -o Org1MSP -o OrdererMSP

## add user key and cert to org1.yaml from admin-ordservice.yaml
kubectl hlf utils adduser --userPath=peer-org1.yaml --config=org1.yaml --username=admin --mspid=Org1MSP

#Join channel
kubectl hlf channel join --name=demo --config=org1.yaml \
    --user=admin -p=org1-peer0.default

#Inspect the channel
kubectl hlf channel inspect --channel=demo --config=org1.yaml \
    --user=admin -p=org1-peer0.default > demo.json

#Add anchor peer
kubectl hlf channel addanchorpeer --channel=demo --config=org1.yaml \
    --user=admin --peer=org1-peer0.default


#INSTALL A CHAINCODE
# remove the code.tar.gz asset-transfer-basic-external.tgz if they exist
rm code.tar.gz asset-transfer-basic-external.tgz
export CHAINCODE_NAME=asset
export CHAINCODE_LABEL=asset
cat << METADATA-EOF > "metadata.json"
{
    "type": "ccaas",
    "label": "${CHAINCODE_LABEL}"
}
METADATA-EOF

cat > "connection.json" <<CONN_EOF
{
  "address": "${CHAINCODE_NAME}:7052",
  "dial_timeout": "10s",
  "tls_required": false
}
CONN_EOF

tar cfz code.tar.gz connection.json
tar cfz asset-transfer-basic-external.tgz metadata.json code.tar.gz
export PACKAGE_ID=$(kubectl hlf chaincode calculatepackageid --path=asset-transfer-basic-external.tgz --language=node --label=$CHAINCODE_LABEL)
echo "PACKAGE_ID=$PACKAGE_ID"

kubectl hlf chaincode install --path=./asset-transfer-basic-external.tgz \
    --config=org1.yaml --language=golang --label=$CHAINCODE_LABEL --user=admin --peer=org1-peer0.default

# this can take 3-4 minutes


#Deploy chaincode
kubectl hlf externalchaincode sync --image=kfsoftware/chaincode-external:latest \
    --name=$CHAINCODE_NAME \
    --namespace=default \
    --package-id=$PACKAGE_ID \
    --tls-required=false \
    --replicas=1

#Query chaincodes installed
kubectl hlf chaincode queryinstalled --config=org1.yaml --user=admin --peer=org1-peer0.default

#Approve chaincode
export SEQUENCE=1
export VERSION="1.0"
kubectl hlf chaincode approveformyorg --config=org1.yaml --user=admin --peer=org1-peer0.default \
    --package-id=$PACKAGE_ID \
    --version "$VERSION" --sequence "$SEQUENCE" --name=asset \
    --policy="OR('Org1MSP.member')" --channel=demo

#Commit chaincode
kubectl hlf chaincode commit --config=org1.yaml --user=admin --mspid=Org1MSP \
    --version "$VERSION" --sequence "$SEQUENCE" --name=asset \
    --policy="OR('Org1MSP.member')" --channel=demo

sleep 45s

#Invoke a transaction in the ledger
kubectl hlf chaincode invoke --config=org1.yaml \
    --user=admin --peer=org1-peer0.default \
    --chaincode=asset --channel=demo \
    --fcn=initLedger -a '[]'

#Query the ledger
kubectl hlf chaincode query --config=org1.yaml \
    --user=admin --peer=org1-peer0.default \
    --chaincode=asset --channel=demo \
    --fcn=GetAllAssets -a '[]'
