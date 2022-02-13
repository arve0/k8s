DOMAIN ?= arve.dev
EMAIL ?= arve+k8s@seljebu.no
USERNAME ?= arve

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

letsencrypt: FORCE
	kubectl wait pod --for=condition=Ready -l app=webhook -n cert-manager --timeout=120s
	EMAIL=${EMAIL} envsubst < cert-manager/letsencrypt.yaml \
		| kubectl apply -f -

uninstall-cert-manager:
	kubectl kustomize cert-manager \
		| kubectl delete -f -
	kubectl delete -n kube-system configmap cert-manager-cainjector-leader-election
	kubectl delete -n kube-system configmap cert-manager-controller
	kubectl delete -A service -l acme.cert-manager.io/http01-solver=true
	kubectl delete -A ingress -l acme.cert-manager.io/http01-solver=true

registry/password:
	if kubectl get secret registry-auth -n internal &>/dev/null; then \
		kubectl get secret registry-auth -n internal -o json \
			| jq --raw-output .data.password \
			| base64 -d > registry/password ; \
	else \
		dd if=/dev/urandom bs=30 count=1 2>/dev/null | base64 > registry/password; \
	fi

registry: registry/password FORCE
	kubectl kustomize registry \
		| DOMAIN=${DOMAIN} envsubst \
		| kubectl apply -f -

	htpasswd -ic auth ${USERNAME} < registry/password

	if ! kubectl get secret registry-auth -n internal &>/dev/null; then \
		kubectl create secret generic registry-auth -n internal --from-file=auth --from-file=registry/password; \
	fi
	rm auth

registry-login: registry/password
	docker login registry.apps.${DOMAIN} --username ${USERNAME} --password-stdin < registry/password

list-repos: registry/password
	curl -u arve:$$(cat registry/password) https://registry.apps.arve.dev/v2/_catalog

docker-pull-secret: registry/password
	kubectl delete secret registry-credentials -n default || true
	kubectl create secret docker-registry registry-credentials \
		--namespace=default \
		--docker-server=registry.apps.${DOMAIN} \
		--docker-username=${USERNAME} \
		--docker-password=$$(cat registry/password)
	kubectl patch serviceaccount default -n default -p '{"imagePullSecrets": [{"name": "registry-credentials"}]}'


FORCE: