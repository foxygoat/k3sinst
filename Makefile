# --- Install -----------------------------------------------------------------

INSTALL_DIR = /usr/local/sbin
K3S_DATA_DIR = /opt/k3s
K3S_SYMLINKS = kubectl crictl ctr
SYSTEMD_DIR = /etc/systemd/system

export INSTALL_DIR K3S_DATA_DIR

install: install-k3s install-k3s-links install-systemd install-dirs

install-k3s:
	sudo ./scripts/get-k3s
	sudo install -m 0755 -o root -g root scripts/k3s-killall.sh $(INSTALL_DIR)

install-k3s-links: | $(K3S_SYMLINKS:%=$(INSTALL_DIR)/%)
$(K3S_SYMLINKS:%=$(INSTALL_DIR)/%):
	sudo ln -nsf k3s $@

install-systemd: $(SYSTEMD_DIR)/multi-user.target.wants/k3s@server.service
$(SYSTEMD_DIR)/multi-user.target.wants/k3s@server.service: $(SYSTEMD_DIR)/k3s@.service
	sudo systemctl enable k3s@server

$(SYSTEMD_DIR)/k3s@.service: systemd/k3s@.service
	sudo install -m 644 -o root -g root $< $@
	sudo systemctl daemon-reload

install-dirs:
	sudo install -d -m 0750 -g adm $(K3S_DATA_DIR)/pv
	sudo install -d -m 2750 -g adm $(K3S_DATA_DIR)/etc

uninstall:
	-sudo $(INSTALL_DIR)/k3s-killall.sh
	-sudo systemctl disable k3s@server
	sudo systemctl daemon-reload
	sudo rm -f $(SYSTEMD_DIR)/k3s@.service
	sudo rm -f $(INSTALL_DIR)/k3s-* $(INSTALL_DIR)/k3s
	sudo rm -f $(K3S_SYMLINKS:%=$(INSTALL_DIR)/%)
	sudo rm -rf $(K3S_DATA_DIR)

.PHONY: install install-k3s install-k3s-links install-systemd install-dirs uninstall

install-tools:
	(cd /tmp; GO111MODULE=on go get github.com/bitnami/kubecfg)
	(cd /tmp; GO111MODULE=on go get github.com/bitnami-labs/sealed-secrets/cmd/kubeseal)

# --- Deploy ------------------------------------------------------------------

DEPLOYMENTS = sealed-secrets cert-manager metallb traefik
KUBECONFIG=$(K3S_DATA_DIR)/etc/kubeconfig.yaml
KUBECFG=kubecfg
KUBECTL=kubectl
export KUBECONFIG

deploy: $(DEPLOYMENTS:%=deploy-%)
undeploy: $(DEPLOYMENTS:%=undeploy-%)

deploy-%:
	$(KUBECTL) apply -R -f manifests/$*

undeploy-%:
	$(KUBECTL) delete -R -f manifests/$*

deploy-metallb-secret:
	$(KUBECFG) -V rand="$$(openssl rand -base64 128)" update manifests/metallb/memberlist.jsonnet

.PHONY: deploy undeploy deploy-metallb-secret
