#!/bin/sh
set -e

gum confirm 'Are you ready to start?' || exit 0

echo "
## You will need following tools installed:
|Name            |Required             |More info                                          |
|----------------|---------------------|---------------------------------------------------|
|git CLI         |Yes                  |'https://git-scm.com/downloads'                    |
|yq CLI          |Yes                  |'https://github.com/mikefarah/yq#install'          |
|kubectl CLI     |Yes                  |'https://kubernetes.io/docs/tasks/tools/#kubectl'  |
|helm CLI        |Yes                  |'https://helm.sh/docs/intro/install/'              |
|Kubernetes cluster with an Ingress controller|The script can create a cluster in Civo|    |
|civo CLI        |If setup should create a cluster|'https://civo.com/docs/overview/civo-cli#installation'|
|Civo account    |If setup should create a cluster|'https://dashboard.civo.com/signup'|

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of a **Kubernetes cluster** (unless you choose the script to create it for you).
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

rm -f .env

###########
# Cluster #
###########

echo "## Cluster" | gum format

gum confirm "
Do you have a Kubernetes cluster (it cannot be a local one like Minikube or KinD)?" \
    && CLUSTER=true || CLUSTER=false

if [[ "$CLUSTER" != "true" ]]; then

    gum confirm "Would you like this script to create a Civo cluster?" \
        && CIVO=true || CIVO=false

    if [[ "$CIVO" == "true" ]]; then

        echo "export CLUSTER=civo" >> .env

        CIVO_TOKEN=$(gum input --placeholder "Civo token" --value "$CIVO_TOKEN")
        echo "export CIVO_TOKEN=$CIVO_TOKEN" >> .env

        civo apikey save dot $CIVO_TOKEN

        civo kubernetes create dot --size g4s.kube.medium \
            --remove-applications=Traefik-v2-nodeport \
            --applications civo-cluster-autoscaler,traefik2-loadbalancer \
            --nodes 1 --region NYC1 --yes --wait

        sleep 10

        KUBECONFIG=$PWD/kubeconfig.yaml
        echo "export KUBECONFIG=$KUBECONFIG" >> .env

        rm -f $KUBECONFIG

        civo kubernetes config dot --region NYC1 \
            --local-path $KUBECONFIG --save

        chmod 400 $KUBECONFIG

        echo "## Waiting for the external IP of the Ingress Service (2 min.)..." \
            | gum format
        sleep 120

        INGRESS_HOST=$(kubectl --namespace kube-system \
            get service traefik \
            --output jsonpath="{.status.loadBalancer.ingress[0].ip}"
        )

        INGRESS_CLASS=traefik

    else

        echo "## You MUST have a Kubernetes cluster to continue." \
            | gum format

        exit 0

    fi

else

    echo '### You can get the IP by observing the `EXTERNAL-IP` column from the output of `kubectl get services --all-namespaces`.' \
        | gum format

    INGRESS_HOST=$(gum input --placeholder "Ingress Service external IP" --value "$INGRESS_HOST")

    INGRESS_CLASS=$(kubectl get ingressclasses \
        --output jsonpath="{.items[0].metadata.name}")

fi

kubectl create namespace a-team

#############
# Manifests #
#############

echo "## Manifests" | gum format

yq --inplace ".spec.ingressClassName = \"$INGRESS_CLASS\"" \
    silly-demo/ingress.yaml

yq --inplace ".spec.rules[0].host = \"silly-demo.$INGRESS_HOST.nip.io\"" \
    silly-demo/ingress.yaml

yq --inplace ".spec.ingressClassName = \"$INGRESS_CLASS\"" \
    silly-demo-mem/ingress.yaml

yq --inplace ".spec.rules[0].host = \"silly-demo-mem.$INGRESS_HOST.nip.io\"" \
    silly-demo-mem/ingress.yaml

##############
# PostgreSQL #
##############

echo "## PostgreSQL" | gum format

helm upgrade --install cnpg cloudnative-pg \
    --repo https://cloudnative-pg.github.io/charts \
    --namespace cnpg-system --create-namespace --wait

########
# Apps #
########

echo "## Apps" | gum format

kubectl --namespace a-team apply --filename silly-demo/

kubectl --namespace a-team apply --filename silly-demo-mem/

kubectl --namespace a-team apply --filename cnpg.yaml

########
# Misc #
########

chmod +x destroy.sh

#################
# Perfect Scale #
#################

echo "## Perfect Scale" | gum format

echo '### Open https://perfectscale.io in a browser, login, click the `+ Add cluster`, and follow the instructions.' \
    | gum format