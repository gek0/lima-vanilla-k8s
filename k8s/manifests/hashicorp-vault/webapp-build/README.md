# vault-webapp-example

Simple Python web app that reads secrets from HashiCorp Vault using Kubernetes service account authentication.

## Build (examples with Podman and Docker Hub)

- latest tag is `1.0.1`

Notes:
- Make sure you are logged in to Docker Hub with Podman (replace `mburisa93` with your Docker Hub username!):
```bash
    podman login docker.io
```


1. Build for Each Architecture
```bash
podman build --arch amd64 -t mburisa93/vault-webapp-example:amd64-1.0.1 .
podman build --arch arm64 -t mburisa93/vault-webapp-example:arm64-1.0.1 .
```

2. Create a Manifest
```bash
podman manifest create mburisa93/vault-webapp-example:1.0.1
```

3. Add Images to the Manifest
```bash
podman manifest add mburisa93/vault-webapp-example:1.0.1 docker-daemon:mburisa93/vault-webapp-example:amd64-1.0.1
podman manifest add mburisa93/vault-webapp-example:1.0.1 docker-daemon:mburisa93/vault-webapp-example:arm64-1.0.1
```

4. Push the Manifest to Docker Hub
```bash
podman manifest push --all mburisa93/vault-webapp-example:1.0.1 docker://docker.io/mburisa93/vault-webapp-example:1.0.1
```

## Versioning

Update the image tag in `../webapp-manifests.yaml` after pushing a new version.

## Dependencies

| Package | Version |
|---|---|
| Python | 3.13-slim |
| requests | 2.32.3 |
