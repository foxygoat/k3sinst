# k3s install and setup

This repo contains the scripts and manifests to install and set up a
simple k3s Kubernetes cluster. Because I have to do everything my own
way, bit by bit, this repo will grow to take over any default set up by
k3s.

## Installing k3s

### Dependencies

* bash
* curl
* go 1.15
* jq
* make

Install these with your OS package manager.

### k3s binary installation

This repo has a `Makefile` and download script to download and install
k3s, instead of using the k3s-provided method of curl-downloading a
shell script and piping it into `sh` as root. It is not as flexible as
the k3s installation script, but I don't need it to be. Start installing
a k3s cluster with:

    make install

or

    make install-k3s install-k3s-links install-systemd install-dirs

This will install to `/opt/k3s` by default. To change this, set the
`DIR` variable on the command line:

    make DIR=/srv/k3s install

To undo all that `make install` does, run

    make uninstall

Warning: This will delete any data in any local persistent volumes that
containers may have created, but only those you have configured with
persistent storage.

### Launching k3s

    systemctl start k3s@server

k3s is launched from systemd using the systemd service file in the
`systemd` directory. It is a service template and is installed as either
`k3s@server` or `k3s@agent`. The former is a master and node, the latter
is just a node. Currently it is only installed as a server.

k3s is started with some defaults hard-coded into the systemd service
file. It puts all the data in the `/opt/k3s` directory (or whatever
`DIR` was set to). k3s includes a local path provider
(https://rancher.com/docs/k3s/latest/en/storage/) which is configured to
put data under `/opt/k3s/pv`. You may want to back this up to preserve
persistent volumes used by workloads.

If you have re-run `make install` to install a newer version of k3s,
restart it with:

    systemctl restart k3s@server

### Configuration

When k3s starts, it puts a kubeconfig file in `/opt/k3s/etc` that
contains the connection parameters and keys/certs to talk to the API
server. It creates a symlink to that kubeconfig file as
`/etc/rancher/k3s/k3s.yaml`. A symlink for `kubectl` is installed in
`/usr/local/sbin` that knows to look at that kubeconfig file, but if
other tools are used that need to talk to the API server (such as
kubecfg for example), you will need to setup your environment:

    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

Access to the kubeconfig file gives admin-level access to the cluster.
It is protected so that it is only readable by `root` and members of the
`adm` group. Add yourself to the `adm` group if you want to run
Kubernetes commands as a regular user.

### Reinstalling

For continuity through an uninstall and install (re-installation) some
secrets may need to be preserved. Before running `make uninstall` you
can run `make save-secrets` which will pull secrets from the cluster and
put it in the manifest directory ready to be installed in the next
cluster.

The secrets are left unencrypted in the filesystem, so when you are done
re-installing the cluster, run `make clean-secrets` to remove them.

The full re-install sequence would be (if you install metallb):

    make save-secrets
    make uninstall
    make install
    make deploy-metallb-secret
    make deploy
    make clean-secrets

If you don't install metallb:
    make save-secrets
    make uninstall
    make install
    make deploy-sealed-secrets deploy-cert-manager deploy-traefik
    make clean-secrets

At this stage, the only secrets saved are the sealed-secrets sealing
keys. Usually all other secrets are sealed with sealed-secrets, so this
should be all that needs to be preserved in order to reload existing
sealed secrets.

## Service Deployment

### Installing Tools

Some extra tools are needed by the manifests to install them. They are
installed by running:

    make install-tools

This will install tools needed to install and use the services
installed in the cluster.

### Installing Kubernetes Services

Manifests in the `manifests` directory are for infrastructure services
that we always want in a new cluster. New services are added to the
`DEPLOYMENTS` variable in the `Makefile` and can be deployed by running

    make deploy

Some services may require additional one-time setup. They will add
additional deployment targets to the `Makefile` and be listed and
documented here.

`make deploy` can be re-run to upgrade any components that may have
changed in this repository.

### Traefik

If the traefik config file has been changed
(`manifests/traefik/50_configmap.yaml`), you will need to restart
traefik as it does not detect changes to it:

    kubectl delete pod -n traefik -l app=traefik

The Deployment controller will take care of starting a new pod after you
delete the existing one.
