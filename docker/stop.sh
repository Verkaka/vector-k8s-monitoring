#!/bin/bash

# Vector 监控栈 - Docker 停止脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 停止 Vector 监控栈..."
echo ""

if docker compose version &> /dev/null; then
    docker compose down
else
    docker-compose down
fi

echo ""
echo "✅ 服务已停止"
echo ""
echo "💡 清理数据卷（可选）:"
echo "   docker compose down -v"
echo ""
echo "💡 删除所有容器和镜像:"
echo "   docker compose down --rmi all --volumes"
