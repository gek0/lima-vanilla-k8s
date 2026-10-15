# Hashicorp Vault (dev environment)

Vault HA Raft setup + example webapp that reads secrets from it.

## Installation

Run from master:
```
./scripts/manifest-installer.sh
```
Select `hashicorp-vault`. The installer runs these steps automatically:
1. **`setup-requirements-service.sh`** — adds HashiCorp Helm repo and installs Vault via Helm
2. Applies `vault-manifests.yaml` (namespace, PVs, PVCs, VirtualService)
3. Waits for PVC to be bound
4. **`patch-service.sh`** — exposes via MetalLB, initializes Vault, unseals all pods, joins Raft cluster

> After install, if pods are stuck in Pending: SSH to each Worker node and run `sudo chmod -R 757 /tmp/vault`

> `cluster-keys.json` (unseal key + root token) is written to this directory — keep it safe, it is gitignored.

## Working with Vault secrets

Exec into vault-0 and log in with the root token from `cluster-keys.json`:
```
kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh
vault login
```

Enable kv-v2 secrets and create a sample secret:
```
vault secrets enable -path=secret kv-v2
vault kv put secret/webapp/config username="user" password="pass"
```

Enable Kubernetes auth and wire up the webapp service account:
```
vault auth enable kubernetes
vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

vault policy write webapp - <<EOF
path "secret/data/webapp/config" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/webapp \
  bound_service_account_names=webapp \
  bound_service_account_namespaces=vault \
  policies=webapp \
  ttl=24h
```

## Sample webapp

```
kubectl apply -f webapp-manifests.yaml
kubectl port-forward -n vault service/webapp 8000:80
curl http://localhost:8000/get/env
```
