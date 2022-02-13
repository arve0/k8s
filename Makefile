DOMAIN ?= arve.dev
EMAIL ?= arve+k8s@seljebu.no

ingress/ingress.yaml: Makefile
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm template ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx \
		> ingress/ingress.yaml

ingress: ingress/ingress.yaml FORCE
	kubectl kustomize ingress \
		| DOMAIN=${DOMAIN} envsubst \
		| kubectl apply -f -

cert-manager/cert-manager.yaml: Makefile
	helm repo add jetstack https://charts.jetstack.io
	helm template cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--set installCRDs=true \
		> cert-manager/cert-manager.yaml

cert-manager: cert-manager/cert-manager.yaml FORCE
	kubectl kustomize cert-manager \
		| kubectl apply -f -
	kubectl wait pod --for=condition=Ready -l app=webhook -n cert-manager --timeout=120s
	EMAIL=${EMAIL} envsubst < cert-manager/letsencrypt.yaml \
		| kubectl apply -f -

FORCE: