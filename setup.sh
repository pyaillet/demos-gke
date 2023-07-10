#!/usr/bin/env bash

echo "* Check cluster existence"
gcloud container clusters describe cluster-1 --zone europe-north1-a
CLUSTER_EXISTS=$?
echo $CLUSTER_EXISTS
if [[ $CLUSTER_EXISTS -ne "0" ]]; then
  echo "* Creating the GKE cluster"
  gcloud container clusters create cluster-1 --zone europe-north1-a --spot
fi

echo "* Check traefik helm repo existence"
helm repo list | grep traefik
TRAEFIK_REPO_EXISTS=$?
if [[ $TRAEFIK_REPO_EXISTS -ne "0" ]]; then
  echo "* Creating the traefik helm repo"
  helm repo add traefik https://traefik.github.io/charts 
fi

helm repo update traefik

helm upgrade --install traefik traefik/traefik -n traefik-ingress --create-namespace --repo https://traefik.github.io/charts 

echo "* Waiting for ingress controller to get an IP address.."
until [[ $(kubectl get svc -n traefik-ingress traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]]; do sleep 5; echo -n "."; done
export EXTERNAL_IP="$(kubectl get svc -n traefik-ingress traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo ""
echo "* Ingress external IP: ${EXTERNAL_IP}"

echo "* Deploying argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
echo "* Waiting for argocd-server to get an IP address.."
until [[ $(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]]; do sleep 5; echo -n "."; done
export ARGOCD_EXTERNAL_IP="$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo ""
echo "* Argocd external IP: ${ARGOCD_EXTERNAL_IP}"

echo "* Deploying argocd rollout"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

export ARGOCD_INITIAL_PASSWORD="$(kubectl get secrets -n argocd argocd-initial-admin-secret --template='{{.data.password}}' | base64 -d)"

echo "* Check open-telemetry helm repo existence"
helm repo list | grep open-telemetry
OTEL_REPO_EXISTS=$?
if [[ $OTEL_REPO_EXISTS -ne "0" ]]; then
  echo "* Creating the open-telemetry helm repo"
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
fi
helm repo update open-telemetry

echo "* Installing Open-telemetry demo"
cat ./opentelemetry/values.yaml | envsubst > ./opentelemetry/values-lb.yaml
helm upgrade --install my-otel-demo open-telemetry/opentelemetry-demo --namespace otel --create-namespace --values ./opentelemetry/values-lb.yaml

echo "***************************"
echo "* Deployment successful   *"
echo "***************************"
echo
echo "External IP Address: ${EXTERNAL_IP}"
echo
echo "ArgoCD IP Address: ${ARGOCD_EXTERNAL_IP}"
echo "ArgoCD Initial Password: \"${ARGOCD_INITIAL_PASSWORD}\""
echo
echo "Opentelemetry App:              http://otel-demo.${EXTERNAL_IP}.nip.io/"
echo "Opentelemetry Grafana:          http://otel-demo.${EXTERNAL_IP}.nip.io/grafana/"
echo "Opentelemetry Feature flags UI: http://otel-demo.${EXTERNAL_IP}.nip.io/feature/"
echo "Opentelemetry Load generator:   http://otel-demo.${EXTERNAL_IP}.nip.io/loadgen/"
echo "Opentelemetry Jaeger:           http://otel-demo.${EXTERNAL_IP}.nip.io/jaeger/ui/"

