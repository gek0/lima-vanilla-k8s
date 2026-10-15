# Hashicorp Vault (dev environment)

Vault HA Raft setup + example webapp that reads secrets from it.


## Working with Vault secrets

After the installation is completed "Root token" can be found in `cluster-keys.json` file and used in further steps!

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

- prebuild image available on https://hub.docker.com/r/mburisa93/vault-webapp-example
 - re-build and update manually from `webapp-build` directory

```
kubectl apply -f webapp-build/webapp-manifests.yaml

# run port-forward...

curl http://localhost:<SERVICE_PORT>/get/env
```
