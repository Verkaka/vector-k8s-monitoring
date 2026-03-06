#!/bin/bash

# Vector 监控栈 - Docker 快速启动脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Vector 监控栈 - Docker 部署"
echo "================================"
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose 未安装"
    exit 1
fi

echo "✅ Docker 和 Docker Compose 已安装"
docker --version
docker compose version 2>/dev/null || docker-compose --version
echo ""

# 创建必要的目录
echo "📁 创建目录结构..."
mkdir -p grafana/provisioning/dashboards
mkdir -p grafana/provisioning/datasources
echo "✅ 目录已创建"
echo ""

# 复制 Dashboard
echo "📊 配置 Grafana Dashboard..."
if [ -f "../grafana-dashboard.json" ]; then
    cp ../grafana-dashboard.json grafana-dashboard.json
    echo "✅ Dashboard 已复制"
else
    echo "⚠️  Dashboard 文件不存在，使用基础配置"
fi
echo ""

# 启动服务
echo "🚀 启动服务..."
if docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi
echo ""

# 等待服务就绪
echo "⏳ 等待服务启动..."
sleep 10

# 检查服务状态
echo "📊 检查服务状态..."
if docker compose version &> /dev/null; then
    docker compose ps
else
    docker-compose ps
fi
echo ""

# 显示访问信息
echo "================================"
echo "✅ 部署完成！"
echo "================================"
echo ""
echo "🌐 访问地址:"
echo "   - Grafana:    http://localhost:3000"
echo "                 用户名：admin"
echo "                 密码：admin"
echo ""
echo "   - Prometheus: http://localhost:9091"
echo "                 查询：vector_build_info"
echo ""
echo "   - Vector:     http://localhost:9090/metrics"
echo ""
echo "📋 常用命令:"
echo ""
echo "   # 查看日志"
echo "   docker compose logs -f vector"
echo "   docker compose logs -f prometheus"
echo "   docker compose logs -f grafana"
echo ""
echo "   # 停止服务"
echo "   docker compose down"
echo ""
echo "   # 重启服务"
echo "   docker compose restart"
echo ""
echo "   # 查看 metrics"
echo "   curl http://localhost:9090/metrics"
echo ""
echo "   # 测试 Prometheus 查询"
echo "   curl 'http://localhost:9091/api/v1/query?query=vector_build_info'"
echo ""
echo "📊 Grafana Dashboard:"
echo "   1. 登录 Grafana (http://localhost:3000)"
echo "   2. 导航到 Dashboards → Vector"
echo "   3. 查看 Vector Metrics Dashboard"
echo ""
echo "🔍 Prometheus 查询示例:"
echo "   - vector_build_info"
echo "   - rate(vector_processed_events_total[5m])"
echo "   - rate(vector_component_errors_total[5m])"
echo "   - container_memory_usage_bytes"
echo ""
echo "🎉 测试完成！"
