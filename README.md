# n8n Self-Hosted Deployment with Webhook Processors

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

This repository provides a complete solution for self-hosting n8n with webhook processors, similar to the setup provided by Railway.com but optimized for self-managed servers (like Hetzner Cloud) and Coolify.io.

## 🏗️ Architecture Overview

The deployment consists of five main components:

1. **Primary n8n**: Handles the UI and editor
2. **Worker n8n**: Processes workflow executions
3. **Webhook Processor**: Handles incoming webhook requests
4. **PostgreSQL**: Database for storing workflows and execution data
5. **Redis**: Message broker for communication between components

![Architecture Diagram]([https://github.com/AiRchrdMendez/self-host-n8n-with-webhook-processors/blob/main/README.md))

## ✨ Features

- **Scalable Architecture**: Separate webhook processors and workers for better performance
- **SSL Support**: Automatic SSL certificate management with Let's Encrypt
- **High Availability**: Ability to scale webhook processors and workers
- **Backup & Restore**: Included scripts for easy backup and recovery
- **Deployment Options**: Deploy directly with Docker Compose or via Coolify.io
- **Customizable Configuration**: Easy configuration through environment variables

## 🚀 Deployment Options

### Option 1: Direct Deployment with Docker Compose

Perfect for deploying directly on a VPS with Docker installed.

1. Clone this repository:
   ```bash
   git clone https://github.com/AiRchrdMendez/n8n-self-hosted.git
   cd n8n-self-hosted
   ```

2. Configure your environment:
   ```bash
   cp .env.example .env
   nano .env  # Edit your configuration
   ```

3. Run the setup script:
   ```bash
   chmod +x scripts/setup.sh
   ./scripts/setup.sh
   ```

4. Start the services:
   ```bash
   docker compose up -d
   ```

### Option 2: Deployment with Coolify.io

Perfect for those using Coolify.io for server management.

1. In your Coolify dashboard, create a new "Service Stack"
2. Select "Docker Compose" as the build pack
3. Connect this GitHub repository
4. Select the `docker-compose.coolify.yml` file
5. Configure the environment variables
6. Deploy the stack

## 🛠️ Configuration

### Required Environment Variables

|
 Variable 
|
 Description 
|
 Default 
|
|
----------
|
-------------
|
---------
|
|
`DOMAIN`
|
 Your domain for n8n 
|
 n8n.yourdomain.com 
|
|
`N8N_ENCRYPTION_KEY`
|
 Encryption key for n8n credentials 
|
 (random generated) 
|
|
`N8N_USER_MANAGEMENT_JWT_SECRET`
|
 JWT secret for user management 
|
 (random generated) 
|
|
`POSTGRES_PASSWORD`
|
 PostgreSQL password 
|
 change_me_please 
|
|
`REDIS_PASSWORD`
|
 Redis password 
|
 change_me_also_please 
|
|
`SSL_EMAIL`
|
 Email for Let's Encrypt registration 
|
 your-email@example.com 
|

For a complete list of all available configuration options, see the [.env.example](.env.example) file.

## 🔄 Scaling

You can scale the webhook processors and workers by increasing the number of replicas:

### For Docker Compose:

Edit the `docker-compose.yml` file:

```yaml
n8n-worker:
  deploy:
    replicas: 3  # Adjust as needed

n8n-webhook:
  deploy:
    replicas: 2  # Adjust as needed
```

### For Coolify.io:

In the Coolify dashboard, go to your n8n service, and adjust the number of replicas for the worker and webhook services.

## 💾 Backup and Restore

### Creating a Backup

Run the backup script to create a complete backup of your n8n instance:

```bash
./scripts/backup.sh
```

This will create a backup file in the `./backups` directory.

### Restoring from a Backup

To restore your n8n instance from a backup:

```bash
./scripts/restore.sh ./backups/n8n_backup_YYYYMMDDHHMMSS.tar.gz
```

## 🔒 Security Recommendations

1. Use strong passwords for PostgreSQL and Redis
2. Generate strong random encryption keys for n8n
3. Restrict access to your server using a firewall
4. Set up regular backups
5. Keep your n8n instance and Docker images updated

## 📚 Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Community Forum](https://community.n8n.io/)
- [Coolify Documentation](https://coolify.io/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

⭐ If this repository helps you, consider giving it a star on GitHub! ⭐
