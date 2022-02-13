DOMAIN ?= arve.dev

ingress/ingress.yaml: Makefile
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm template ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx \
		> ingress/ingress.yaml

ingress: ingress/ingress.yaml FORCE
	kubectl kustomize ingress \
		| DOMAIN=${DOMAIN} envsubst \
		| kubectl apply -f -

FORCE: