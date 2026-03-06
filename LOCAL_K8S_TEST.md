# Vector K8s 监控 - 本地测试指南

## 🎯 本地测试方案

### 方案一：Minikube（推荐）

适合完整功能测试，支持所有 K8s 特性。

#### 安装 Minikube

```bash
# macOS
brew install minikube

# Linux
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

#### 启动集群

```bash
minikube start --cpus=2 --memory=4g --disk-size=20g
```

#### 部署

```bash
cd ~/.openclaw/workspace-dev/vector-k8s-monitoring

# 自动部署脚本
./test-local-k8s.sh

# 或手动部署
kubectl create namespace monitoring
kubectl apply -f vector-configmap.yaml -n monitoring
kubectl apply -f vector-deployment.yaml -n monitoring
kubectl apply -f prometheus-servicemonitor.yaml -n monitoring
```

---

### 方案二：Kind（轻量快速）

适合快速测试，启动速度快。

#### 安装 Kind

```bash
# macOS
brew install kind

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

#### 启动集群

```bash
kind create cluster --name vector-test
```

#### 部署

```bash
kubectl create namespace monitoring
kubectl apply -f vector-configmap.yaml -n monitoring
kubectl apply -f vector-deployment.yaml -n monitoring
```

---

### 方案三：Docker Desktop K8s

如果你使用 Docker Desktop，可以直接启用 K8s。

#### 启用 K8s

1. 打开 Docker Desktop
2. Settings → Kubernetes → Enable Kubernetes
3. 等待启动完成

#### 验证

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🚀 快速测试

### 1. 运行自动化脚本

```bash
cd ~/.openclaw/workspace-dev/vector-k8s-monitoring
chmod +x test-local-k8s.sh
./test-local-k8s.sh
```

脚本会自动：
- ✅ 检查 kubectl 和集群
- ✅ 创建命名空间
- ✅ 部署 Vector
- ✅ 配置 ServiceMonitor
- ✅ 验证 Metrics endpoint
- ✅ 显示访问方式

### 2. 验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n monitoring -l app=vector

# 查看日志
kubectl logs -n monitoring -l app=vector -f

# 端口转发
kubectl port-forward svc/vector-metrics -n monitoring 9090:9090

# 测试 metrics
curl http://localhost:9090/metrics
```

### 3. 访问 Dashboard

```bash
# Minikube
minikube dashboard

# 或访问 Vector metrics
minikube service vector-metrics -n monitoring --url
```

---

## 📊 完整测试流程

### 步骤 1: 启动 K8s 集群

```bash
# Minikube
minikube start --cpus=2 --memory=4g

# Kind
kind create cluster --name vector-test
```

### 步骤 2: 部署 Vector

```bash
cd ~/.openclaw/workspace-dev/vector-k8s-monitoring

kubectl create namespace monitoring
kubectl apply -f vector-configmap.yaml -n monitoring
kubectl apply -f vector-deployment.yaml -n monitoring
kubectl apply -f prometheus-servicemonitor.yaml -n monitoring
kubectl apply -f vector-alerts.yaml -n monitoring
```

### 步骤 3: 等待就绪

```bash
kubectl wait --for=condition=Ready pod -l app=vector -n monitoring --timeout=300s
```

### 步骤 4: 验证 Metrics

```bash
# 获取 Pod 名称
VECTOR_POD=$(kubectl get pods -n monitoring -l app=vector -o jsonpath="{.items[0].metadata.name}")

# 端口转发
kubectl port-forward pod/$VECTOR_POD -n monitoring 9090:9090 &

# 测试 metrics
curl http://localhost:9090/metrics | head -30
```

### 步骤 5: 部署 Prometheus Stack（可选）

```bash
# 添加 Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 安装 kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.serviceMonitorSelectorNilUsesHelmValues=false
```

### 步骤 6: 访问 Grafana

```bash
# 端口转发
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# 默认密码
# 用户名：admin
# 密码：prom-operator (通过以下命令获取)
kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
```

---

## 🔍 验证检查清单

### K8s 资源

- [ ] Namespace `monitoring` 已创建
- [ ] Vector DaemonSet 已部署
- [ ] Vector Pod 状态为 Running
- [ ] Service `vector-metrics` 已创建
- [ ] ServiceMonitor 已创建（如果有 Prometheus Operator）

### Metrics 验证

- [ ] `curl http://localhost:9090/metrics` 返回数据
- [ ] 包含 `vector_build_info`
- [ ] 包含 `vector_processed_events_total`
- [ ] Prometheus 能抓取到 metrics

### 日志验证

- [ ] `kubectl logs -n monitoring -l app=vector` 显示日志
- [ ] 能看到 Docker 日志收集
- [ ] 没有错误信息

---

## 🛠️ 故障排查

### 问题 1: Pod 无法启动

```bash
# 查看 Pod 状态
kubectl describe pod -n monitoring -l app=vector

# 查看日志
kubectl logs -n monitoring -l app=vector

# 检查 RBAC
kubectl get clusterrole vector
kubectl get clusterrolebinding vector
```

### 问题 2: Metrics 无法访问

```bash
# 检查 Service
kubectl get svc -n monitoring vector-metrics

# 检查端口
kubectl get endpoints -n monitoring vector-metrics

# 测试连接
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://vector-metrics.monitoring.svc:9090/metrics
```

### 问题 3: Prometheus 无法发现

```bash
# 检查 ServiceMonitor
kubectl get servicemonitor -n monitoring vector

# 检查 Prometheus targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090
# 访问 http://localhost:9090/targets
```

---

## 📈 性能测试

### 生成测试负载

```bash
# 创建测试 Pod 生成日志
kubectl run log-generator --image=busybox -n default --restart=Never -- \
  sh -c 'while true; do echo "Test log $(date)"; sleep 1; done'
```

### 观察指标

```bash
# 事件处理率
curl http://localhost:9090/metrics | grep vector_processed_events_total

# 错误数
curl http://localhost:9090/metrics | grep vector_component_errors_total
```

---

## 🧹 清理环境

```bash
# 删除命名空间
kubectl delete namespace monitoring

# 删除集群（Minikube）
minikube delete

# 删除集群（Kind）
kind delete cluster --name vector-test
```

---

## 📚 参考链接

- **Minikube 文档**: https://minikube.sigs.k8s.io/docs/
- **Kind 文档**: https://kind.sigs.k8s.io/
- **Vector 文档**: https://vector.dev/docs/
- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator

---

**更新时间**: 2026-03-06  
**维护**: @dev
