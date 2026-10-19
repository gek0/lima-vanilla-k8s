# Grafana - Claude MCP Connection

## Prerequisites

- [uvx](https://github.com/astral-sh/uv) installed
- A running Grafana instance with port forwarding active

## 1. Create a Grafana Service Account

In Grafana: **Administration → Users and access → Service accounts**

1. Create a new service account named `claude-mcp-grafana`
2. Generate a token for it and store it securely

## 2. Configure the MCP Server

### Option A — Add via CLI

```bash
claude mcp add grafana -- uvx mcp-grafana
```

### Option B — Add to `.claude/settings.local.json`

```json
{
  "permissions": {},
  "mcpServers": {
    "grafana": {
      "command": "uvx",
      "args": ["mcp-grafana"],
      "env": {
        "GRAFANA_URL": "http://localhost:<PORT_GIVEN_DURING_FORWARDING>",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "<YOUR_TOKEN_HERE>"
      }
    }
  }
}
```

Replace `<PORT_GIVEN_DURING_FORWARDING>` with the port from your active port-forward session (see `port-forward.sh`), and `<YOUR_TOKEN_HERE>` with the service account token generated in step 1.

## 3. Example Usage

Once connected, you can ask Claude things like:

### Dashboards

```
What dashboards do I have?
Show me the Kubernetes / Compute Resources / Cluster dashboard summary.
Search for dashboards tagged "kubernetes-mixin".
```

### Metrics (Prometheus)

```
Query CPU usage across all nodes for the last 30 minutes.
List all available Prometheus metric names.
Show me memory usage per namespace.
```

### Logs (Loki)

```
Show me logs from the kube-system namespace in the last 15 minutes.
List all Loki label names.
Find error logs from the coredns pod.
```

### Alerts

```
List all active alert rules.
Show me firing alerts.
Are there any silenced alerts?
```

### Incidents

```
List open incidents.
```

### Cluster health (via Prometheus)

```
Is the cluster healthy? Check node status.
Show me pod restart counts across all namespaces.
How many pods are running vs pending vs failed?
```
