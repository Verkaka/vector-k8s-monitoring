# Vector 监控栈 - Docker 快速测试指南

## 📊 架构

```
┌──────────────────────────────────────────────┐
│              Docker Host                      │
│                                               │
│  ┌─────────┐    ┌─────────┐    ┌──────────┐ │
│  │ Vector  │───▶│Prometheus│───▶│ Grafana  │ │
│  │ :9090   │    │ :9091    │    │ :3000    │ │
│  └─────────┘    └─────────┘    └──────────┘ │
│       ▲                                      │
│       │                                      │
│  ┌────┴──────┐                              │
│  │Docker Logs│                              │
│  │Host Metrics│                             │
│  └───────────┘                              │
└──────────────────────────────────────────────┘
```

---

## 🚀 快速开始

### 1. 启动服务

```bash
cd ~/.openclaw/workspace-dev/vector-k8s-monitoring/docker

# 方式一：使用启动脚本
./start.sh

# 方式二：手动启动
docker compose up -d
```

### 2. 验证服务

```bash
# 检查容器状态
docker compose ps

# 查看 Vector 日志
docker compose logs -f vector

# 测试 Vector metrics
curl http://localhost:9090/metrics

# 测试 Prometheus
curl 'http://localhost:9091/api/v1/query?query=vector_build_info'
```

### 3. 访问 Web UI

| 服务 | URL | 凭证 |
|------|-----|------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9091 | - |
| Vector Metrics | http://localhost:9090/metrics | - |

---

## 📁 目录结构

```
docker/
├── docker-compose.yml              # Docker Compose 配置
├── vector.toml                     # Vector 配置
├── prometheus.yml                  # Prometheus 配置
├── start.sh                        # 启动脚本
├── stop.sh                         # 停止脚本
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── datasources.yml     # 数据源配置
│       └── dashboards/
│           └── dashboards.yml      # Dashboard 配置
└── grafana-dashboard.json          # Vector Dashboard (自动复制)
```

---

## 🔍 验证步骤

### 步骤 1: 检查 Vector Metrics

```bash
curl http://localhost:9090/metrics | head -30
```

**预期输出**:
```promql
# HELP vector_build_info Vector build information
# TYPE vector_build_info gauge
vector_build_info{arch="x86_64",os="linux",version="0.35.0"} 1

# HELP vector_processed_events_total Total number of events processed
# TYPE vector_processed_events_total counter
vector_processed_events_total{component_name="docker_logs"} 1234
```

### 步骤 2: 检查 Prometheus 抓取

访问：http://localhost:9091/targets

**预期**:
- `vector` job 状态为 **UP**
- `node-exporter` job 状态为 **UP**

### 步骤 3: 测试 Prometheus 查询

访问：http://localhost:9091/graph

**查询示例**:
```promql
# Vector 版本信息
vector_build_info

# 事件处理率
rate(vector_processed_events_total[5m])

# 错误数
vector_component_errors_total

# 系统内存使用
node_memory_MemTotal_bytes
```

### 步骤 4: 导入 Grafana Dashboard

1. 访问 http://localhost:3000
2. 登录：admin / admin
3. 导航到 **Dashboards** → **Vector**
4. 查看 **Vector Metrics Dashboard**

如果 Dashboard 未自动加载：
1. **Dashboards** → **Import**
2. 上传 `grafana-dashboard.json`
3. 选择 **Prometheus** 数据源
4. 点击 **Import**

---

## 📊 Dashboard 面板

### 实时监控

- **Vector Pods Running** - 运行状态
- **Events Processed Rate** - 事件处理速率
- **Bytes Processed Rate** - 数据处理速率
- **Component Errors** - 组件错误
- **Memory Usage** - 内存使用
- **CPU Usage** - CPU 使用

### Docker 特定指标

- **Docker 容器日志** - 实时日志流
- **容器资源使用** - CPU/内存
- **网络流量** - 收发数据

### 系统指标

- **主机 CPU** - 使用率
- **主机内存** - 使用量
- **磁盘 I/O** - 读写速率
- **网络接口** - 流量统计

---

## 🔧 配置自定义

### 修改 Vector 配置

编辑 `vector.toml`，然后重启：

```bash
docker compose restart vector
```

### 添加新的数据源

在 `vector.toml` 中添加：

```toml
# 示例：收集 Nginx 日志
[sources.nginx_logs]
type = "file"
include = ["/var/log/nginx/access.log"]
```

### 修改 Prometheus 抓取间隔

编辑 `prometheus.yml`：

```yaml
global:
  scrape_interval: 30s  # 改为 30 秒
```

重启 Prometheus：

```bash
docker compose restart prometheus
```

### 修改 Grafana 配置

编辑 `docker/grafana/provisioning/` 下的文件，然后重启：

```bash
docker compose restart grafana
```

---

## 🛠️ 常用命令

### 服务管理

```bash
# 启动
docker compose up -d

# 停止
docker compose down

# 重启
docker compose restart

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f vector
docker compose logs -f prometheus
docker compose logs -f grafana
```

### 调试

```bash
# 进入 Vector 容器
docker compose exec vector sh

# 进入 Prometheus 容器
docker compose exec prometheus sh

# 进入 Grafana 容器
docker compose exec grafana sh

# 测试 metrics
curl http://localhost:9090/metrics

# 测试 Prometheus API
curl 'http://localhost:9091/api/v1/query?query=up'
```

### 清理

```bash
# 停止并删除容器
docker compose down

# 停止并删除容器和数据卷
docker compose down -v

# 删除所有相关镜像
docker compose down --rmi all
```

---

## 🎯 测试场景

### 场景 1: 生成测试日志

```bash
# 运行一个生成日志的容器
docker run --rm alpine sh -c 'while true; do echo "Test log $(date)"; sleep 1; done'
```

然后查看 Vector 是否收集到日志：

```bash
docker compose logs -f vector | grep "Test log"
```

### 场景 2: 测试告警

在 Prometheus 中测试告警查询：

```promql
# 模拟高错误率
vector_component_errors_total > 0

# 模拟无事件
rate(vector_processed_events_total[5m]) == 0
```

### 场景 3: 压力测试

```bash
# 生成大量日志
docker run --rm alpine sh -c 'for i in $(seq 1 10000); do echo "Log line $i"; done'
```

观察 Prometheus 和 Grafana 中的指标变化。

---

## 🔍 故障排查

### 问题 1: Vector 无法启动

```bash
# 查看日志
docker compose logs vector

# 检查配置
docker compose exec vector vector validate --config-dir /etc/vector/
```

### 问题 2: Prometheus 无法抓取 Vector

```bash
# 检查网络
docker compose exec prometheus wget -qO- http://vector:9090/metrics

# 检查 targets
curl http://localhost:9091/api/v1/targets
```

### 问题 3: Grafana 无数据

1. 检查数据源配置
2. 在 Grafana Explore 中测试查询
3. 检查时间范围

---

## 📈 性能优化

### Vector 优化

```toml
# 增加缓冲区大小
[sinks.prometheus_exporter]
type = "prometheus_exporter"
buffer.type = "memory"
buffer.max_events = 10000
```

### Prometheus 优化

```yaml
# 调整保留时间
command:
  - '--storage.tsdb.retention.time=30d'
  - '--storage.tsdb.retention.size=10GB'
```

### Grafana 优化

```yaml
# 调整缓存
environment:
  - GF_DATAPROXY_TIMEOUT=60
  - GF_ALERTING_EVALUATION_TIMEOUT=30
```

---

## 🎓 学习资源

- **Vector 文档**: https://vector.dev/docs/
- **Prometheus 文档**: https://prometheus.io/docs/
- **Grafana 文档**: https://grafana.com/docs/
- **Docker Compose**: https://docs.docker.com/compose/

---

## ✅ 检查清单

- [ ] Docker 和 Docker Compose 已安装
- [ ] 运行 `./start.sh`
- [ ] 所有容器状态为 Up
- [ ] Vector metrics 可访问 (:9090)
- [ ] Prometheus 可访问 (:9091)
- [ ] Grafana 可访问 (:3000)
- [ ] Dashboard 已导入
- [ ] 能够查询到数据
- [ ] 日志正常收集

---

**更新时间**: 2026-03-06  
**Vector 版本**: 0.35.0  
**Prometheus 版本**: 2.48.0  
**Grafana 版本**: 10.2.2  
**维护**: @dev
