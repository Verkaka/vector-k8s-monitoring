#!/bin/bash

# Vector K8s 监控部署和测试脚本
set -e

NAMESPACE="monitoring"
WORKSPACE="$HOME/.openclaw/workspace-dev/vector-k8s-monitoring"

echo "🚀 Vector K8s 监控部署和测试脚本"
echo "================================="
echo ""

# ==================== 1. 检查前置条件 ====================
echo "📋 步骤 1: 检查前置条件"

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装，请先安装 kubectl"
    exit 1
fi
echo "✅ kubectl 已安装"

# 检查集群连接
echo "🔗 检查 Kubernetes 集群连接..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ 无法连接到 Kubernetes 集群"
    echo "💡 请确保："
    echo "   1. kubectl 已正确配置"
    echo "   2. 集群正在运行"
    echo "   3. kubeconfig 文件正确 (~/.kube/config)"
    exit 1
fi
echo "✅ 已连接到 Kubernetes 集群"
kubectl cluster-info | head -2
echo ""

# 检查 Prometheus Operator
echo "📊 检查 Prometheus Operator..."
if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
    echo "✅ Prometheus Operator 已安装"
    USE_SERVICE_MONITOR=true
else
    echo "⚠️  Prometheus Operator 未安装，将使用静态配置"
    USE_SERVICE_MONITOR=false
fi
echo ""

# ==================== 2. 创建命名空间 ====================
echo "📋 步骤 2: 创建命名空间"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "✅ 命名空间 $NAMESPACE 已创建"
echo ""

# ==================== 3. 部署 Vector ====================
echo "📋 步骤 3: 部署 Vector"

cd "$WORKSPACE"

echo "📦 应用 Vector 配置..."
kubectl apply -f vector-configmap.yaml -n $NAMESPACE
kubectl apply -f vector-deployment.yaml -n $NAMESPACE

echo "⏳ 等待 Vector Pod 就绪..."
kubectl wait --for=condition=Ready pod -l app=vector -n $NAMESPACE --timeout=120s || {
    echo "⚠️  Vector Pod 未能在 2 分钟内就绪"
    kubectl get pods -n $NAMESPACE -l app=vector
    exit 1
}

echo "✅ Vector 已部署"
kubectl get pods -n $NAMESPACE -l app=vector
echo ""

# ==================== 4. 配置监控 ====================
echo "📋 步骤 4: 配置 Prometheus 监控"

if [ "$USE_SERVICE_MONITOR" = true ]; then
    echo "📦 应用 ServiceMonitor..."
    kubectl apply -f prometheus-servicemonitor.yaml -n $NAMESPACE
    echo "✅ ServiceMonitor 已创建"
else
    echo "⚠️  跳过 ServiceMonitor (Prometheus Operator 未安装)"
    echo "💡  请手动配置 Prometheus scrape 配置："
    echo ""
    echo "   scrape_configs:"
    echo "     - job_name: 'vector'"
    echo "       kubernetes_sd_configs:"
    echo "         - role: pod"
    echo "       relabel_configs:"
    echo "         - source_labels: [__meta_kubernetes_pod_label_app]"
    echo "           action: keep"
    echo "           regex: vector"
fi
echo ""

# ==================== 5. 验证 Metrics ====================
echo "📋 步骤 5: 验证 Vector Metrics"

echo "🔍 获取 Vector Pod 名称..."
VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath="{.items[0].metadata.name}")
echo "Vector Pod: $VECTOR_POD"

echo "📊 测试 metrics endpoint..."
kubectl port-forward pod/$VECTOR_POD -n $NAMESPACE 9090:9090 &
PORT_FORWARD_PID=$!
sleep 3

# 测试 metrics
if curl -s http://localhost:9090/metrics | head -20; then
    echo "✅ Metrics endpoint 正常工作"
    echo ""
    
    # 显示关键 metrics
    echo "📈 关键 Metrics:"
    echo "---------------"
    curl -s http://localhost:9090/metrics | grep -E "^vector_(build_info|processed_events_total|component_errors_total)" | head -10
else
    echo "❌ Metrics endpoint 无法访问"
fi

# 清理 port-forward
kill $PORT_FORWARD_PID 2>/dev/null || true
echo ""

# ==================== 6. 部署告警规则 ====================
echo "📋 步骤 6: 配置告警规则"

if [ "$USE_SERVICE_MONITOR" = true ]; then
    kubectl apply -f vector-alerts.yaml -n $NAMESPACE
    echo "✅ 告警规则已创建"
    kubectl get prometheusrule -n $NAMESPACE
else
    echo "⚠️  跳过告警规则 (Prometheus Operator 未安装)"
fi
echo ""

# ==================== 7. 导入 Grafana Dashboard ====================
echo "📋 步骤 7: 导入 Grafana Dashboard"

echo "💡 请按以下步骤导入 Dashboard："
echo ""
echo "   1. 登录 Grafana"
echo "   2. 导航到 Dashboards → Import"
echo "   3. 上传文件：$WORKSPACE/grafana-dashboard.json"
echo "   4. 选择 Prometheus 数据源"
echo "   5. 点击 Import"
echo ""
echo "   或者使用命令行 (需要 Grafana CLI):"
echo "   grafana-cli --admin-url http://<grafana-url> \\"
echo "     --admin-user admin --admin-password <password> \\"
echo "     dashboards import $WORKSPACE/grafana-dashboard.json"
echo ""

# ==================== 8. 显示访问方式 ====================
echo "📋 步骤 8: 访问方式"

echo ""
echo "🌐 访问 Vector Metrics:"
echo "   kubectl port-forward svc/vector-metrics -n $NAMESPACE 9090:9090"
echo "   然后访问：http://localhost:9090/metrics"
echo ""

echo "📊 访问 Grafana Dashboard:"
echo "   1. 导入 grafana-dashboard.json"
echo "   2. 使用变量筛选：Namespace, Pod, Component"
echo ""

echo "🔔 查看告警:"
echo "   Prometheus UI → Alerts"
echo "   或 Grafana → Alerting"
echo ""

# ==================== 9. 测试查询 ====================
echo "📋 步骤 9: Prometheus 查询测试"

echo ""
echo "💡 在 Prometheus UI 中测试以下查询:"
echo ""
echo "   # Vector Pod 数量"
echo "   count(vector_build_info)"
echo ""
echo "   # 事件处理率"
echo "   rate(vector_processed_events_total[5m])"
echo ""
echo "   # 错误率"
echo "   rate(vector_component_errors_total[5m])"
echo ""
echo "   # 内存使用"
echo "   container_memory_usage_bytes{container=\"vector\"}"
echo ""
echo "   # CPU 使用"
echo "   rate(container_cpu_usage_seconds_total{container=\"vector\"}[5m])"
echo ""

# ==================== 10. 清理（可选） ====================
echo "📋 步骤 10: 清理（可选）"
echo ""
echo "💡 如需删除 Vector 监控，执行:"
echo "   kubectl delete namespace $NAMESPACE"
echo ""
echo "   或删除单个资源:"
echo "   kubectl delete -f vector-deployment.yaml -n $NAMESPACE"
echo "   kubectl delete -f vector-configmap.yaml -n $NAMESPACE"
echo "   kubectl delete -f prometheus-servicemonitor.yaml -n $NAMESPACE"
echo "   kubectl delete -f vector-alerts.yaml -n $NAMESPACE"
echo ""

# ==================== 完成 ====================
echo "================================="
echo "✅ Vector K8s 监控部署完成！"
echo "================================="
echo ""
echo "📁 项目文件:"
echo "   - vector-configmap.yaml: Vector 配置"
echo "   - vector-deployment.yaml: DaemonSet + Service + RBAC"
echo "   - prometheus-servicemonitor.yaml: Prometheus 自动发现"
echo "   - vector-alerts.yaml: 12 个告警规则"
echo "   - grafana-dashboard.json: 13 个面板的 Dashboard"
echo "   - README.md: 完整文档"
echo ""
echo "🔗 GitHub 仓库:"
echo "   https://github.com/Verkaka/vector-k8s-monitoring"
echo ""
echo "📊 Dashboard ID: vector-overview"
echo "🔔 告警规则：12 个 (Critical: 3, Warning: 8, Info: 1)"
echo ""
echo "🎉 测试完成！"
