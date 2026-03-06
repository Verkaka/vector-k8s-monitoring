#!/bin/bash

# Vector K8s 监控 - 本地测试脚本
set -e

WORKSPACE="$HOME/.openclaw/workspace-dev/vector-k8s-monitoring"
NAMESPACE="monitoring"

echo "🚀 Vector K8s 监控 - 本地测试"
echo "================================"
echo ""

# ==================== 检查环境 ====================
echo "📋 步骤 1: 检查环境"

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl 未安装"
    echo "💡 安装：brew install kubectl"
    exit 1
fi
echo "✅ kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# 检查集群
if kubectl cluster-info &> /dev/null; then
    CLUSTER=$(kubectl config current-context)
    echo "✅ K8s 集群：$CLUSTER"
    USE_CLUSTER=true
else
    echo "⚠️  未检测到 K8s 集群"
    USE_CLUSTER=false
fi

# 检查 minikube
if command -v minikube &> /dev/null; then
    echo "✅ minikube: $(minikube version --short)"
fi

# 检查 kind
if command -v kind &> /dev/null; then
    echo "✅ kind: $(kind version)"
fi

echo ""

# ==================== 启动集群 ====================
if [ "$USE_CLUSTER" = false ]; then
    echo "📋 步骤 2: 启动本地集群"
    echo ""
    echo "请选择集群方案:"
    echo "  1) minikube (推荐，功能完整)"
    echo "  2) kind (轻量快速)"
    echo "  3) 手动启动后继续"
    echo ""
    read -p "选择 [1-3]: " choice
    
    case $choice in
        1)
            echo "🚀 启动 minikube..."
            minikube start --cpus=2 --memory=4g
            ;;
        2)
            echo "🚀 启动 kind..."
            kind create cluster --name vector-test
            ;;
        3)
            echo "⏳ 等待手动启动集群..."
            read -p "按回车继续"
            ;;
        *)
            echo "❌ 无效选择"
            exit 1
            ;;
    esac
fi

echo ""

# ==================== 创建命名空间 ====================
echo "📋 步骤 3: 创建命名空间"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "✅ 命名空间 $NAMESPACE 已创建"
echo ""

# ==================== 部署 Vector ====================
echo "📋 步骤 4: 部署 Vector"

cd "$WORKSPACE"

echo "📦 应用 Vector 配置..."
kubectl apply -f vector-configmap.yaml -n $NAMESPACE
kubectl apply -f vector-deployment.yaml -n $NAMESPACE

echo "⏳ 等待 Vector Pod 就绪..."
kubectl wait --for=condition=Ready pod -l app=vector -n $NAMESPACE --timeout=300s || {
    echo "⚠️  Vector Pod 未能在 5 分钟内就绪"
    kubectl get pods -n $NAMESPACE -l app=vector
    kubectl describe pod -n $NAMESPACE -l app=vector | tail -20
    exit 1
}

echo "✅ Vector 已部署"
kubectl get pods -n $NAMESPACE -l app=vector
echo ""

# ==================== 配置监控 ====================
echo "📋 步骤 5: 配置 Prometheus"

# 检查 Prometheus Operator
if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null 2>&1; then
    echo "✅ Prometheus Operator 已安装"
    kubectl apply -f prometheus-servicemonitor.yaml -n $NAMESPACE
    echo "✅ ServiceMonitor 已创建"
else
    echo "⚠️  Prometheus Operator 未安装"
    echo ""
    echo "💡 安装 Prometheus Stack (可选):"
    echo "   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
    echo "   helm install prometheus prometheus-community/kube-prometheus-stack -n $NAMESPACE"
    echo ""
fi
echo ""

# ==================== 验证 Metrics ====================
echo "📋 步骤 6: 验证 Metrics"

VECTOR_POD=$(kubectl get pods -n $NAMESPACE -l app=vector -o jsonpath="{.items[0].metadata.name}")
echo "Vector Pod: $VECTOR_POD"

echo "📊 测试 metrics endpoint..."
kubectl port-forward pod/$VECTOR_POD -n $NAMESPACE 9090:9090 &
PORT_FORWARD_PID=$!
sleep 3

if curl -s http://localhost:9090/metrics | head -20; then
    echo "✅ Metrics endpoint 正常工作"
    echo ""
    echo "📈 关键 Metrics:"
    curl -s http://localhost:9090/metrics | grep -E "^vector_(build_info|processed_events_total)" | head -5
else
    echo "❌ Metrics endpoint 无法访问"
fi

kill $PORT_FORWARD_PID 2>/dev/null || true
echo ""

# ==================== 显示访问方式 ====================
echo "================================"
echo "✅ 部署完成！"
echo "================================"
echo ""

if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    echo "🌐 Minikube 访问方式:"
    echo ""
    echo "   # 开启 dashboard"
    echo "   minikube dashboard"
    echo ""
    echo "   # 访问 Vector metrics"
    echo "   minikube service vector-metrics -n $NAMESPACE --url"
    echo ""
fi

echo "📋 常用命令:"
echo ""
echo "   # 查看 Pod 状态"
echo "   kubectl get pods -n $NAMESPACE -l app=vector"
echo ""
echo "   # 查看日志"
echo "   kubectl logs -n $NAMESPACE -l app=vector -f"
echo ""
echo "   # 端口转发"
echo "   kubectl port-forward svc/vector-metrics -n $NAMESPACE 9090:9090"
echo ""
echo "   # 测试 metrics"
echo "   curl http://localhost:9090/metrics"
echo ""
echo "   # 清理"
echo "   kubectl delete namespace $NAMESPACE"
echo ""

echo "🔍 Prometheus 查询示例:"
echo "   - vector_build_info"
echo "   - rate(vector_processed_events_total[5m])"
echo "   - rate(vector_component_errors_total[5m])"
echo ""

echo "🎉 测试完成！"
