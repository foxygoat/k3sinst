# --- Install -----------------------------------------------------------------

DIR = /opt/k3s
INSTALL_DIR = /usr/local/sbin
K3S_DATA_DIR = $(DIR)
K3S_SYMLINKS = kubectl crictl ctr
SYSTEMD_DIR = /etc/systemd/system

export INSTALL_DIR K3S_DATA_DIR

install: install-k3s install-k3s-links install-systemd install-dirs
upgrade: install-k3s restart-k3s

install-k3s: $(INSTALL_DIR)/k3s-killall.sh
	sudo ./scripts/get-k3s

$(INSTALL_DIR)/k3s-killall.sh: scripts/k3s-killall.sh
	sudo install -m 0755 -o root -g root $< $@

install-k3s-links: | $(K3S_SYMLINKS:%=$(INSTALL_DIR)/%)
$(K3S_SYMLINKS:%=$(INSTALL_DIR)/%):
	sudo ln -nsf k3s $@

install-systemd: $(SYSTEMD_DIR)/multi-user.target.wants/k3s@server.service
	echo 'K3S_DATA_DIR=$(K3S_DATA_DIR)' | sudo tee $(SYSTEMD_DIR)/k3s.env > /dev/null

$(SYSTEMD_DIR)/multi-user.target.wants/k3s@server.service: $(SYSTEMD_DIR)/k3s@.service
	sudo systemctl enable k3s@server

$(SYSTEMD_DIR)/k3s@.service: systemd/k3s@.service
	sudo install -m 644 -o root -g root $< $@
	sudo systemctl daemon-reload

restart-k3s:
	sudo systemctl restart k3s@server

install-dirs:
	sudo install -d -m 0750 -g adm $(K3S_DATA_DIR)/pv
	sudo install -d -m 2750 -g adm $(K3S_DATA_DIR)/etc

uninstall:
	-sudo $(INSTALL_DIR)/k3s-killall.sh
	-sudo systemctl disable k3s@server
	sudo systemctl daemon-reload
	sudo rm -f $(SYSTEMD_DIR)/k3s@.service $(SYSTEMD_DIR)/k3s.env
	sudo rm -f $(INSTALL_DIR)/k3s-* $(INSTALL_DIR)/k3s
	sudo rm -f $(K3S_SYMLINKS:%=$(INSTALL_DIR)/%)
	sudo rm -rf $(K3S_DATA_DIR)

.PHONY: install install-k3s install-k3s-links install-systemd install-dirs uninstall

install-tools:
	(cd /tmp; GO111MODULE=on go get github.com/bitnami-labs/sealed-secrets/cmd/kubeseal)

# --- Deploy ------------------------------------------------------------------

DEPLOYMENTS = sealed-secrets cert-manager metallb traefik
KUBECONFIG=/etc/rancher/k3s/k3s.yaml
KUBECTL=kubectl
export KUBECONFIG

deploy: $(DEPLOYMENTS:%=deploy-%)
undeploy: $(DEPLOYMENTS:%=undeploy-%)

deploy-%:
	$(KUBECTL) apply -R -f manifests/$*

undeploy-%:
	$(KUBECTL) delete -R -f manifests/$*

.PHONY: deploy undeploy deploy-metallb-secret

# --- Secret Saving -----------------------------------------------------------

save-secrets: save-sealed-secrets
clean-secrets: clean-sealed-secrets

SS_SECRET = manifests/sealed-secrets/01_master.yaml

save-sealed-secrets:
	$(KUBECTL) get secret -n kube-system \
		-l sealedsecrets.bitnami.com/sealed-secrets-key \
		-o yaml \
		> $(SS_SECRET)

clean-sealed-secrets:
	shred --zero --remove $(SS_SECRET)

.PHONY: clean-secrets save-secrets
.PHONY: clean-sealed-secrets save-sealed-secrets

# --- Update manifests --------------------------------------------------------

CM_VERSION = v1.10.1
CM_SOURCE = https://github.com/cert-manager/cert-manager/releases/download/$(CM_VERSION)/cert-manager.yaml
CM_MANIFEST = manifests/cert-manager/cert-manager.yaml
CM_TMP = /tmp/cert-manager.yaml

update-cert-manager:
	curl -fsSL -o "$(CM_TMP)" "$(CM_SOURCE)"
	kubecfg show --reorder server "$(CM_TMP)" > "$(CM_MANIFEST)"
	rm "$(CM_TMP)"

MLB_VERSION = v0.13.7
MLB_SOURCE = https://raw.githubusercontent.com/metallb/metallb/$(MLB_VERSION)/config/manifests/metallb-native.yaml
MLB_MANIFEST = manifests/metallb/metallb-native.yaml
MLB_TMP = /tmp/metallb-native.yaml

update-metallb:
	curl -fsSL -o "$(MLB_TMP)" "$(MLB_SOURCE)"
	kubecfg show --reorder server "$(MLB_TMP)" > "$(MLB_MANIFEST)"
	rm "$(MLB_TMP)"

SS_VERSION = v0.19.2
SS_SOURCE = https://github.com/bitnami-labs/sealed-secrets/releases/download/$(SS_VERSION)/controller.yaml
SS_MANIFEST = manifests/sealed-secrets/cotroller.yaml
SS_TMP = /tmp/controller.yaml

update-sealed-secrets:
	curl -fsSL -o "$(SS_TMP)" "$(SS_SOURCE)"
	kubecfg show --reorder server "$(SS_TMP)" > "$(SS_MANIFEST)"
	rm "$(SS_TMP)"

TRAEFIK_VERSION = v2.8.1
TRAEFIK_HELM_VERSION = v10.24.0
TRAEFIK_HELM_ARCHIVE = https://github.com/traefik/traefik-helm-chart/archive
TRAEFIK_RBAC_SOURCE = https://raw.githubusercontent.com/traefik/traefik/$(TRAEFIK_VERSION)/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml
TRAEFIK_RBAC_MANIFEST = manifests/traefik/12_rbac.yaml
TRAEFIK_name_namespace = {"name": "traefik", "namespace": "traefik"}
TRAEFIK_DEPLOYMENT = manifests/traefik/60_deployment.yaml

update-traefik:
	curl -fsSL $(TRAEFIK_HELM_ARCHIVE)/$(TRAEFIK_HELM_VERSION).tar.gz \
		| tar zxf - -C manifests/traefik --strip-components=2 \
			--wildcards '*/traefik/crds/*'
	curl -fsSL "$(TRAEFIK_RBAC_SOURCE)" \
		| yq '(select(.subjects[0]) | .subjects[0]) += $(TRAEFIK_name_namespace)' \
		> "$(TRAEFIK_RBAC_MANIFEST)"
	yq -i '.spec.template.spec.containers[0].image = "traefik:$(TRAEFIK_VERSION)"' $(TRAEFIK_DEPLOYMENT)

.PHONY: update-cert-manager update-metallb update-sealed-secrets update-traefik
