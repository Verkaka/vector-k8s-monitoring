# Vector K8s 监控测试报告

## 📊 测试概览

| 项目 | 状态 | 说明 |
|------|------|------|
| 仓库创建 | ✅ | https://github.com/Verkaka/vector-k8s-monitoring |
| CI/CD 配置 | ⏸️ | 可选配置 |
| 代码推送 | ✅ | 6 个文件已推送 |
| Kubernetes 部署 | ⚠️ | 需要 K8s 集群 |
| 测试脚本 | ✅ | deploy-and-test.sh |

---

## 📁 项目文件清单

```
vector-k8s-monitoring/
├── vector-configmap.yaml          # Vector 配置 (internal_metrics + prometheus_exporter)
├── vector-deployment.yaml         # DaemonSet + Service + RBAC + ServiceAccount
├── prometheus-servicemonitor.yaml # ServiceMonitor + PodMonitor
├── vector-alerts.yaml             # 12 个 Prometheus 告警规则
├── grafana-dashboard.json         # 13 个面板的 Dashboard
├── deploy-and-test.sh             # 自动化部署和测试脚本
└── README.md                      # 完整配置指南
```

---

## 🚀 部署测试

### 方式一：自动化脚本（推荐）

```bash
cd ~/.openclaw/workspace-dev/vector-k8s-monitoring
./deploy-and-test.sh
```

脚本会自动执行：

1. ✅ 检查 kubectl 和集群连接
2. ✅ 检查 Prometheus Operator
3. ✅ 创建 monitoring 命名空间
4. ✅ 部署 Vector (ConfigMap + DaemonSet)
5. ✅ 配置 ServiceMonitor
6. ✅ 验证 Metrics endpoint
7. ✅ 部署告警规则
8. ✅ 提供 Grafana Dashboard 导入指南
9. ✅ 显示访问方式和测试查询
10. ✅ 提供清理命令

### 方式二：手动部署

```bash
# 1. 创建命名空间
kubectl create namespace monitoring

# 2. 部署 Vector
kubectl apply -f vector-configmap.yaml -n monitoring
kubectl apply -f vector-deployment.yaml -n monitoring

# 3. 等待 Pod 就绪
kubectl wait --for=condition=Ready pod -l app=vector -n monitoring --timeout=120s

# 4. 配置监控
kubectl apply -f prometheus-servicemonitor.yaml -n monitoring

# 5. 部署告警
kubectl apply -f vector-alerts.yaml -n monitoring
```

---

## 🧪 验证步骤

### 1. 检查 Pod 状态

```bash
kubectl get pods -n monitoring -l app=vector

# 预期输出
# NAME          READY   STATUS    RESTARTS   AGE
# vector-abc12  1/1     Running   0          2m
# vector-def34  1/1     Running   0          2m
# vector-ghi56  1/1     Running   0          2m
```

### 2. 测试 Metrics Endpoint

```bash
# Port-forward 到 Vector Pod
VECTOR_POD=$(kubectl get pods -n monitoring -l app=vector -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward pod/$VECTOR_POD -n monitoring 9090:9090

# 在另一个终端测试
curl http://localhost:9090/metrics
```

**预期输出**:
```promql
# HELP vector_build_info Vector build information
# TYPE vector_build_info gauge
vector_build_info{arch="x86_64",os="linux",version="0.35.0"} 1

# HELP vector_processed_events_total Total number of events processed
# TYPE vector_processed_events_total counter
vector_processed_events_total{component_name="k8s_logs"} 12345

# HELP vector_component_errors_total Total number of component errors
# TYPE vector_component_errors_total counter
vector_component_errors_total{component_name="k8s_logs"} 0
```

### 3. 验证 Prometheus 抓取

访问 Prometheus UI → **Status** → **Targets**

查找 `vector` job，状态应为 **UP**。

### 4. 测试 Prometheus 查询

在 Prometheus UI 的 **Graph** 页面测试以下查询：

```promql
# Vector Pod 数量
count(vector_build_info)

# 事件处理率
rate(vector_processed_events_total[5m])

# 错误率
rate(vector_component_errors_total[5m])

# 内存使用
container_memory_usage_bytes{container="vector"}

# CPU 使用
rate(container_cpu_usage_seconds_total{container="vector"}[5m])
```

### 5. 导入 Grafana Dashboard

**方式一：UI 导入**
1. 登录 Grafana
2. **Dashboards** → **Import**
3. 上传 `grafana-dashboard.json`
4. 选择 Prometheus 数据源
5. 点击 **Import**

**方式二：使用 Dashboard ID**
```bash
# 如果有 grafana-cli
grafana-cli --admin-url http://<grafana-url> \
  --admin-user admin --admin-password <password> \
  dashboards import grafana-dashboard.json
```

### 6. 验证告警规则

```bash
kubectl get prometheusrule -n monitoring

# 预期输出
# NAME          AGE
# vector-alerts 2m
```

访问 Prometheus UI → **Alerts**，查看 Vector 相关告警规则。

---

## 📈 Dashboard 测试检查清单

导入 Dashboard 后，验证以下面板：

### 顶部统计卡片

- [ ] **Vector Pods Running** - 显示 Pod 数量（应为绿色）
- [ ] **Total Events Processed** - 显示事件数（应有数值）
- [ ] **Total Bytes Processed** - 显示字节数（应有数值）
- [ ] **Processing Errors** - 显示错误数（应为 0 或绿色）

### 时间序列图

- [ ] **Events Processed Rate** - 应有波动曲线
- [ ] **Bytes Processed Rate** - 应有波动曲线
- [ ] **Component Errors** - 应为平线或接近 0
- [ ] **Component Sent Events** - 应有波动曲线
- [ ] **HTTP Requests** - 应有请求（如果有 HTTP 源）
- [ ] **HTTP Request Duration** - P95/P99 延迟
- [ ] **Memory Usage** - 内存使用趋势
- [ ] **CPU Usage** - CPU 使用趋势

### 表格

- [ ] **Vector Components Status** - 显示组件列表

### 变量筛选

- [ ] **Namespace** - 可选择命名空间
- [ ] **Pod** - 可选择特定 Pod
- [ ] **Component** - 可选择组件

---

## 🔔 告警规则测试

### 告警列表

| 告警名称 | 级别 | 触发条件 | 测试方法 |
|---------|------|----------|----------|
| VectorPodDown | 🔴 Critical | Pod 不可用 > 5m | 删除一个 Vector Pod |
| VectorPodsNotReady | 🟡 Warning | Pod 数量 < 3 | 缩减 DaemonSet |
| VectorHighErrorRate | 🟡 Warning | 错误率 > 1% | 配置错误的输出 |
| VectorCriticalErrors | 🔴 Critical | 错误 > 10/min | 配置错误的源 |
| VectorNoEvents | 🟡 Warning | 无事件 > 10m | 停止日志源 |
| VectorLowThroughput | ℹ️ Info | < 100 events/s | 减少日志源 |
| VectorHighMemoryUsage | 🟡 Warning | 内存 > 90% | 增加日志量 |
| VectorMemoryPressure | 🔴 Critical | 内存 > 95% | 限制内存并增加负载 |
| VectorHighCPUUsage | 🟡 Warning | CPU > 80% | 增加处理负载 |
| VectorComponentFailed | 🟡 Warning | 错误 > 100 | 配置故障组件 |
| VectorSinkBackpressure | 🟡 Warning | 无法发送事件 | 停止输出目标 |
| VectorHTTPHighLatency | 🟡 Warning | P95 > 1s | 增加 HTTP 负载 |

### 测试告警（示例）

```bash
# 测试 VectorPodDown 告警
kubectl delete pod -n monitoring -l app=vector --wait=false

# 等待 5 分钟后检查告警
# Prometheus UI → Alerts → VectorPodDown 应为 pending/firing
```

---

## 🔍 故障排查

### 问题 1: Pod 无法启动

```bash
# 检查 Pod 状态
kubectl describe pod -n monitoring -l app=vector

# 查看日志
kubectl logs -n monitoring -l app=vector
```

**常见原因**:
- ConfigMap 配置错误
- RBAC 权限不足
- 节点资源不足

### 问题 2: Metrics 无法访问

```bash
# 检查 Service
kubectl get svc -n monitoring vector-metrics

# 测试连接
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://vector-metrics.monitoring.svc:9090/metrics
```

**常见原因**:
- Port 配置错误
- NetworkPolicy 阻止
- Pod 未监听正确端口

### 问题 3: Prometheus 无法发现

```bash
# 检查 ServiceMonitor
kubectl get servicemonitor -n monitoring vector

# 检查 Prometheus 配置
# Prometheus UI → Status → Configuration
```

**常见原因**:
- label 不匹配
- namespace 配置错误
- Prometheus Operator 未安装

### 问题 4: Grafana 无数据

```bash
# 在 Grafana Explore 中测试查询
vector_build_info
```

**常见原因**:
- Prometheus 数据源配置错误
- 查询语法错误
- 时间范围不对

---

## 📊 性能基准

### 资源使用（每节点）

| 指标 | 预期值 | 说明 |
|------|--------|------|
| CPU | 50-200m | 取决于日志量 |
| 内存 | 200-500Mi | 取决于缓冲大小 |
| 网络 | 1-10Mbps | 取决于日志量 |

### 处理能力

| 场景 | 事件率 | 延迟 |
|------|--------|------|
| 低负载 | < 1K/s | < 1s |
| 中负载 | 1K-10K/s | 1-5s |
| 高负载 | > 10K/s | 5-10s |

---

## ✅ 测试完成检查清单

- [ ] Vector Pod 全部 Running
- [ ] Metrics endpoint 可访问
- [ ] Prometheus 成功抓取
- [ ] Grafana Dashboard 导入成功
- [ ] 所有面板显示数据
- [ ] 告警规则已创建
- [ ] 测试告警触发正常
- [ ] 资源使用在正常范围
- [ ] 日志输出正常（如配置）

---

## 📚 参考链接

- **GitHub 仓库**: https://github.com/Verkaka/vector-k8s-monitoring
- **Vector 文档**: https://vector.dev/docs/
- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator
- **Grafana Dashboards**: https://grafana.com/grafana/dashboards/

---

**测试时间**: 2026-03-06  
**Vector 版本**: 0.35.0  
**测试状态**: ⏳ 待部署  
**维护**: @dev
