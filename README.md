# Kubernetes Vector 监控配置指南

## 📊 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Vector     │    │   Vector     │    │   Vector     │  │
│  │   DaemonSet  │    │   DaemonSet  │    │   DaemonSet  │  │
│  │   (Node 1)   │    │   (Node 2)   │    │   (Node 3)   │  │
│  │   :9090      │    │   :9090      │    │   :9090      │  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘  │
│         │                   │                   │          │
│         └───────────────────┼───────────────────┘          │
│                             │                               │
│                    ┌────────▼────────┐                      │
│                    │   Prometheus    │                      │
│                    │   (Scrape)      │                      │
│                    └────────┬────────┘                      │
│                             │                               │
└─────────────────────────────┼───────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │     Grafana       │
                    │   (Dashboard)     │
                    └───────────────────┘
```

---

## 🚀 快速开始

### 1. 创建命名空间

```bash
kubectl create namespace monitoring
```

### 2. 部署 Vector

```bash
cd vector-k8s-monitoring

# 应用所有配置
kubectl apply -f vector-configmap.yaml
kubectl apply -f vector-deployment.yaml
kubectl apply -f prometheus-servicemonitor.yaml
```

### 3. 验证部署

```bash
# 检查 Vector Pod 状态
kubectl get pods -n monitoring -l app=vector

# 检查 metrics endpoint
kubectl port-forward svc/vector-metrics -n monitoring 9090:9090

# 访问 metrics
curl http://localhost:9090/metrics
```

### 4. 导入 Grafana Dashboard

#### 方式一：通过 Grafana UI

1. 登录 Grafana
2. 导航到 **Dashboards** → **Import**
3. 上传 `grafana-dashboard.json`
4. 选择 Prometheus 数据源
5. 点击 **Import**

#### 方式二：通过 ConfigMap

```bash
# 创建 Dashboard ConfigMap
kubectl create configmap vector-dashboard \
  --from-file=vector-dashboard.json=grafana-dashboard.json \
  -n monitoring

# 添加 Grafana sidecar 注解 (如果使用 grafana-operator)
kubectl annotate configmap vector-dashboard \
  grafana_dashboard=1 \
  -n monitoring
```

---

## 📈 Vector Metrics 说明

### 核心 Metrics

| Metric | 类型 | 说明 |
|--------|------|------|
| `vector_build_info` | Gauge | Vector 版本信息 |
| `vector_processed_events_total` | Counter | 处理的事件总数 |
| `vector_processed_bytes_total` | Counter | 处理的字节总数 |
| `vector_component_errors_total` | Counter | 组件错误数 |
| `vector_component_sent_events_total` | Counter | 组件发送的事件数 |
| `vector_http_requests_total` | Counter | HTTP 请求数 |
| `vector_http_request_duration_seconds` | Histogram | HTTP 请求延迟 |

### 常用查询

```promql
# Vector Pod 数量
count(vector_build_info)

# 每秒处理事件数
rate(vector_processed_events_total[5m])

# 每秒处理字节数
rate(vector_processed_bytes_total[5m])

# 错误率
rate(vector_component_errors_total[5m])

# 按组件统计
sum by (component_name) (rate(vector_component_sent_events_total[5m]))

# Pod 内存使用
container_memory_usage_bytes{container="vector"}

# Pod CPU 使用
rate(container_cpu_usage_seconds_total{container="vector"}[5m])
```

---

## 🔧 Prometheus 配置

### 使用 Prometheus Operator

如果已安装 Prometheus Operator，ServiceMonitor 会自动发现：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vector
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: vector
  endpoints:
    - port: metrics
      interval: 30s
```

### 使用静态配置

编辑 `prometheus.yml`：

```yaml
scrape_configs:
  - job_name: 'vector'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - monitoring
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: vector
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: ${1}
```

---

## 🎯 Grafana Dashboard 面板说明

### 顶部统计卡片

| 面板 | 说明 | 告警阈值 |
|------|------|----------|
| Vector Pods Running | 运行的 Vector Pod 数量 | < 1 红色 |
| Total Events Processed | 1 小时内处理的事件数 | - |
| Total Bytes Processed | 1 小时内处理的字节数 | - |
| Processing Errors | 1 小时内的错误数 | > 10 红色 |

### 时间序列图

| 面板 | 说明 |
|------|------|
| Events Processed Rate | 每秒处理事件数（按 Pod/组件） |
| Bytes Processed Rate | 每秒处理字节数 |
| Component Errors | 组件错误率 |
| Component Sent Events | 组件发送事件数 |
| HTTP Requests | HTTP 请求率 |
| HTTP Request Duration | HTTP 请求延迟 (P95/P99) |
| Memory Usage | 内存使用量 |
| CPU Usage | CPU 使用率 |

### 表格

| 面板 | 说明 |
|------|------|
| Vector Components Status | 各组件状态和发送事件数 |

---

## ⚠️ 告警配置

创建 Prometheus Alerting Rules：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vector-alerts
  namespace: monitoring
spec:
  groups:
    - name: vector.rules
      rules:
        - alert: VectorPodDown
          expr: absent(vector_build_info)
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Vector Pod 不可用"
            description: "Vector Pod 已经停止运行超过 5 分钟"
        
        - alert: VectorHighErrorRate
          expr: |
            sum(rate(vector_component_errors_total[5m])) 
            / sum(rate(vector_processed_events_total[5m])) > 0.01
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Vector 错误率高"
            description: "Vector 错误率超过 1% (当前值：{{ $value }})"
        
        - alert: VectorHighMemoryUsage
          expr: |
            container_memory_usage_bytes{container="vector"} 
            / container_spec_memory_limit_bytes{container="vector"} > 0.9
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Vector 内存使用率高"
            description: "Vector 内存使用超过 90% (当前值：{{ $value | humanizePercentage }})"
        
        - alert: VectorNoEvents
          expr: |
            sum(rate(vector_processed_events_total[5m])) == 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Vector 没有处理事件"
            description: "Vector 已经超过 10 分钟没有处理任何事件"
```

应用告警规则：

```bash
kubectl apply -f vector-alerts.yaml
```

---

## 🔍 故障排查

### 1. Metrics 无法抓取

```bash
# 检查 Pod 状态
kubectl get pods -n monitoring -l app=vector

# 检查 Service
kubectl get svc -n monitoring vector-metrics

# 测试 metrics endpoint
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://vector-metrics.monitoring.svc:9090/metrics
```

### 2. Prometheus 无法发现

```bash
# 检查 ServiceMonitor
kubectl get servicemonitor -n monitoring vector

# 检查 Prometheus targets
# 访问 Prometheus UI → Status → Targets
```

### 3. Grafana 无数据

```bash
# 检查 Prometheus 数据源
# Grafana → Configuration → Data sources → Prometheus

# 测试查询
# Grafana → Explore → 输入查询：vector_build_info
```

---

## 📦 完整文件列表

```
vector-k8s-monitoring/
├── vector-configmap.yaml          # Vector 配置
├── vector-deployment.yaml         # DaemonSet + Service + RBAC
├── prometheus-servicemonitor.yaml # Prometheus 自动发现
├── grafana-dashboard.json         # Grafana Dashboard
├── vector-alerts.yaml             # 告警规则（可选）
└── README.md                      # 本文档
```

---

## 🎨 Dashboard 预览

导入后的 Dashboard 包含：

- **4 个统计卡片** - Pod 数量、事件数、字节数、错误数
- **8 个时间序列图** - 事件率、字节率、错误、HTTP、资源使用
- **1 个表格** - 组件状态详情
- **3 个变量** - Namespace、Pod、Component 筛选

---

## 📚 参考链接

- Vector 官方文档：https://vector.dev/docs/
- Vector Metrics：https://vector.dev/docs/reference/configuration/sources/internal_metrics/
- Grafana Dashboards：https://grafana.com/grafana/dashboards/
- Prometheus Operator：https://github.com/prometheus-operator/prometheus-operator

---

**更新时间**: 2026-03-06  
**Vector 版本**: 0.35.0  
**维护**: @dev
