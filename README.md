# 🐳 EduALL Architecture

---

## 📛 Project Name

**EduALL Docker Production Architecture**

Containerized production architecture for all services and applications within the EduALL ecosystem, based on Docker.

---

## 🎯 Goal

To provide standardized, scalable, and easily manageable deployment infrastructure for the entire EduALL platform by:
- ✅ Isolating each application service in separate containers
- ✅ Centralized network management for inter-service communication
- ✅ Uniform production configuration across all environments
- ✅ Easy deployment, scaling, and maintenance
- ✅ Zero downtime and high availability for EduALL services
- ✅ Standardized developer and production environments

---

## ✨ Key Features

### 🚀 Services Included
| Service | Port | Description |
|---------|------|-------------|
| `php_eduall` | `9001` | EduALL Main Application |
| `php_timesheet` | `9003` | Timesheet Management System |
| `php_assessment` | `9004` | Assessment & Evaluation System |
| `php_crm` | `9006` | EduALL CRM Production |
| `staging_php_crm` | `9007` | EduALL CRM Staging Environment |
| `php_editing_v2` | `9008` | Editing Platform Backend |
| `php_mentoring` | `9009` | Mentoring System Backend |
| `php_authorization` | `9010` | Single Sign On & Authorization Service |
| `php_asset` | `9011` | Asset Management System |
| `php_helpdesk` | `9012` | Helpdesk & Ticketing System |
| `nginx` | `80, 443` | Reverse Proxy + Load Balancer with SSL |
| `redis` | `6379` | Cache & Session Store |
| `n8n` | `5678` | Workflow Automation Engine |

### 🛠️ Architecture Features
- 🔒 SSL Certificate with Lets Encrypt
- 🌐 Single network bridge for all services
- 📂 Persistent volumes for all critical data
- ⚡ Optimized PHP configuration for production
- 📊 Centralized log management
- 🔄 Health check and auto service restart
- 🚀 Production ready configuration

---

## 📖 How To Use

### 1. Start All Services
```bash
docker compose up -d
```

### 2. View Container Status
```bash
docker compose ps
```

### 3. View Service Logs
```bash
# All logs
docker compose logs

# Specific service logs with follow
docker compose logs php_crm -f
```

### 4. Restart Specific Service
```bash
docker compose restart php_timesheet
```

### 5. Stop Services
```bash
# Stop and remove all containers
docker compose down

# Stop containers without removing volumes
docker compose stop
```

### 6. Rebuild Service
```bash
docker compose build --no-cache php_eduall
docker compose up -d php_eduall
```

### 7. Enter Container Shell
```bash
docker compose exec php_crm bash
```

---

## 📝 Important Notes

- All services run inside `app-network` bridge network
- Nginx acts as single entry point for all HTTP/HTTPS requests
- Redis is shared and used by all applications
- SSL certificates are managed externally and mounted to nginx container
- All source code is mounted directly for easy updates