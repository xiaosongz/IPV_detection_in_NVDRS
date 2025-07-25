# IPV Detection System - Deployment Guide

## Overview

This guide covers deployment strategies for the IPV Detection system, including local deployment, server deployment, containerization, and cloud deployment options.

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Deployment Options                        │
├─────────────────┬──────────────────┬───────────────────────┤
│  Local/Desktop  │  Server/HPC      │   Cloud/Container     │
├─────────────────┼──────────────────┼───────────────────────┤
│ • R Studio      │ • Linux Server   │ • Docker              │
│ • Command Line  │ • HPC Cluster    │ • Kubernetes          │
│ • Scheduled     │ • Cron Jobs      │ • AWS/Azure/GCP       │
└─────────────────┴──────────────────┴───────────────────────┘
                            │
                ┌───────────┴────────────┐
                │   Shared Components    │
                ├────────────────────────┤
                │ • Configuration Mgmt   │
                │ • Logging & Monitoring │
                │ • Security & Auth      │
                │ • Backup & Recovery    │
                └────────────────────────┘
```

## Pre-Deployment Checklist

### System Requirements
- **R Version**: 4.2.0 or higher
- **Memory**: Minimum 4GB RAM (8GB recommended)
- **Storage**: 10GB free space for cache and logs
- **Network**: Internet access for API calls (OpenAI) or local network (Ollama)

### Dependencies
```R
# Required R packages
required_packages <- c(
  "tidyverse", "readxl", "writexl", "httr2", "jsonlite",
  "glue", "yaml", "R6", "ratelimitr", "digest", "fs", "optparse"
)

# Installation script
install_dependencies <- function() {
  # Get installed packages
  installed <- installed.packages()[, "Package"]
  
  # Find missing packages
  missing <- setdiff(required_packages, installed)
  
  if (length(missing) > 0) {
    message("Installing missing packages: ", paste(missing, collapse = ", "))
    install.packages(missing, repos = "https://cran.r-project.org")
  } else {
    message("All required packages are installed")
  }
}
```

## Local Deployment

### 1. Basic Setup
```bash
# Clone repository
git clone https://github.com/your-org/IPV_detection_in_NVDRS.git
cd IPV_detection_in_NVDRS

# Install dependencies
Rscript -e 'source("scripts/install_dependencies.R"); install_dependencies()'

# Copy and configure settings
cp config/settings.yml.example config/settings.yml
# Edit config/settings.yml with your API keys and preferences

# Test installation
Rscript R/detect_ipv.R --dry-run
```

### 2. Environment Configuration
```bash
# Create .env file for API keys
cat > .env << EOF
OPENAI_API_KEY=your_key_here
IPVD_ENV=production
EOF

# Or use system environment variables
export OPENAI_API_KEY="your_key_here"
export IPVD_ENV="production"
```

### 3. Scheduled Execution (Windows)
```batch
REM Create batch file: run_ipv_detection.bat
@echo off
cd /d "C:\path\to\IPV_detection_in_NVDRS"
"C:\Program Files\R\R-4.3.0\bin\Rscript.exe" R\detect_ipv.R -i data\narratives.xlsx -o output
```

### 4. Scheduled Execution (macOS/Linux)
```bash
# Create cron job
crontab -e

# Add daily execution at 2 AM
0 2 * * * cd /path/to/IPV_detection_in_NVDRS && /usr/local/bin/Rscript R/detect_ipv.R -i data/narratives.xlsx -o output >> logs/cron.log 2>&1
```

## Server Deployment

### 1. Linux Server Setup
```bash
# Install R
sudo apt-get update
sudo apt-get install -y r-base r-base-dev

# Install system dependencies
sudo apt-get install -y \
  libcurl4-openssl-dev \
  libssl-dev \
  libxml2-dev \
  libfontconfig1-dev

# Clone and setup
git clone https://github.com/your-org/IPV_detection_in_NVDRS.git
cd IPV_detection_in_NVDRS

# Install R packages
sudo Rscript -e 'source("scripts/install_dependencies.R"); install_dependencies()'

# Set up as systemd service
sudo cp deployment/ipv-detection.service /etc/systemd/system/
sudo systemctl enable ipv-detection
sudo systemctl start ipv-detection
```

### 2. Systemd Service Configuration
```ini
# deployment/ipv-detection.service
[Unit]
Description=IPV Detection Service
After=network.target

[Service]
Type=simple
User=ipvdetect
WorkingDirectory=/opt/IPV_detection_in_NVDRS
Environment="OPENAI_API_KEY=your_key_here"
Environment="IPVD_ENV=production"
ExecStart=/usr/bin/Rscript /opt/IPV_detection_in_NVDRS/scripts/continuous_processing.R
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
```

### 3. HPC Cluster Deployment
```bash
#!/bin/bash
# SLURM job script: ipv_detection.sbatch
#SBATCH --job-name=ipv_detection
#SBATCH --output=logs/ipv_%j.out
#SBATCH --error=logs/ipv_%j.err
#SBATCH --time=04:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4

module load R/4.3.0

cd $SLURM_SUBMIT_DIR
Rscript R/detect_ipv.R \
  -i data/narratives.xlsx \
  -o output \
  -c config/hpc_settings.yml
```

## Container Deployment

### 1. Docker Setup
```dockerfile
# Dockerfile
FROM rocker/r-ver:4.3.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy package requirements
COPY scripts/install_dependencies.R .
COPY scripts/required_packages.txt .

# Install R packages
RUN Rscript install_dependencies.R

# Copy application files
COPY R/ ./R/
COPY config/ ./config/

# Create directories
RUN mkdir -p cache logs output data

# Set environment variables
ENV IPVD_ENV=production

# Run script
ENTRYPOINT ["Rscript", "R/detect_ipv.R"]
```

### 2. Docker Compose
```yaml
# docker-compose.yml
version: '3.8'

services:
  ipv-detection:
    build: .
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - IPVD_ENV=production
    volumes:
      - ./data:/app/data
      - ./output:/app/output
      - ./logs:/app/logs
      - ./cache:/app/cache
    command: ["-i", "data/narratives.xlsx", "-o", "output"]
    
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped

volumes:
  ollama_data:
```

### 3. Kubernetes Deployment
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ipv-detection
  labels:
    app: ipv-detection
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ipv-detection
  template:
    metadata:
      labels:
        app: ipv-detection
    spec:
      containers:
      - name: ipv-detection
        image: your-registry/ipv-detection:latest
        env:
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: ipv-secrets
              key: openai-api-key
        - name: IPVD_ENV
          value: "production"
        volumeMounts:
        - name: data
          mountPath: /app/data
        - name: cache
          mountPath: /app/cache
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
          limits:
            memory: "8Gi"
            cpu: "4"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ipv-data-pvc
      - name: cache
        persistentVolumeClaim:
          claimName: ipv-cache-pvc
```

## Cloud Deployment

### AWS Lambda Function
```python
# lambda_function.py
import boto3
import subprocess
import os

def lambda_handler(event, context):
    # Download input from S3
    s3 = boto3.client('s3')
    s3.download_file(
        event['bucket'],
        event['input_key'],
        '/tmp/input.xlsx'
    )
    
    # Run R script
    result = subprocess.run([
        'Rscript',
        '/opt/R/detect_ipv.R',
        '-i', '/tmp/input.xlsx',
        '-o', '/tmp/output'
    ], capture_output=True, text=True)
    
    # Upload results to S3
    output_files = os.listdir('/tmp/output')
    for file in output_files:
        s3.upload_file(
            f'/tmp/output/{file}',
            event['bucket'],
            f"output/{file}"
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Processing complete')
    }
```

### Azure Functions
```json
// function.json
{
  "bindings": [
    {
      "name": "myBlob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "narratives/{name}",
      "connection": "AzureWebJobsStorage"
    },
    {
      "name": "outputBlob",
      "type": "blob",
      "direction": "out",
      "path": "results/{name}_results.csv",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
```

## Security Considerations

### 1. API Key Management
```yaml
# Use secrets management
# Kubernetes secrets
kubectl create secret generic ipv-secrets \
  --from-literal=openai-api-key=$OPENAI_API_KEY

# AWS Secrets Manager
aws secretsmanager create-secret \
  --name ipv-detection/api-keys \
  --secret-string '{"openai_key":"your-key"}'

# Azure Key Vault
az keyvault secret set \
  --vault-name ipv-keyvault \
  --name openai-api-key \
  --value $OPENAI_API_KEY
```

### 2. Network Security
```yaml
# Firewall rules for Ollama
# Allow only from application servers
iptables -A INPUT -p tcp --dport 11434 -s 10.0.0.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 11434 -j DROP
```

### 3. Data Protection
```bash
# Encrypt cache directory
# Linux
sudo apt-get install ecryptfs-utils
sudo mount -t ecryptfs cache cache

# Backup encryption
tar -czf - output/ | openssl enc -aes-256-cbc -out backup.tar.gz.enc
```

## Monitoring Setup

### 1. Health Check Endpoint
```R
# R/health_check.R
library(plumber)

#* @get /health
function() {
  list(
    status = "healthy",
    timestamp = Sys.time(),
    version = "2.0.0",
    providers = list(
      openai = check_openai_health(),
      ollama = check_ollama_health()
    )
  )
}

#* @get /metrics
function() {
  list(
    processed_total = get_metric("processed_total"),
    errors_total = get_metric("errors_total"),
    processing_time_seconds = get_metric("processing_time_seconds")
  )
}
```

### 2. Prometheus Metrics
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'ipv-detection'
    static_configs:
      - targets: ['localhost:8000']
```

### 3. Grafana Dashboard
```json
{
  "dashboard": {
    "title": "IPV Detection Monitoring",
    "panels": [
      {
        "title": "Processing Rate",
        "targets": [
          {
            "expr": "rate(ipv_processed_total[5m])"
          }
        ]
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(ipv_errors_total[5m])"
          }
        ]
      }
    ]
  }
}
```

## Backup and Recovery

### 1. Automated Backups
```bash
#!/bin/bash
# backup.sh
BACKUP_DIR="/backups/ipv-detection"
DATE=$(date +%Y%m%d_%H%M%S)

# Backup cache
tar -czf "$BACKUP_DIR/cache_$DATE.tar.gz" cache/

# Backup output
tar -czf "$BACKUP_DIR/output_$DATE.tar.gz" output/

# Backup logs
tar -czf "$BACKUP_DIR/logs_$DATE.tar.gz" logs/

# Clean old backups (keep 30 days)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
```

### 2. Disaster Recovery
```bash
#!/bin/bash
# restore.sh
BACKUP_FILE=$1

# Extract backup
tar -xzf "$BACKUP_FILE" -C /

# Verify integrity
Rscript -e 'source("scripts/verify_installation.R")'

# Resume processing
Rscript R/detect_ipv.R --resume
```

## Performance Tuning

### 1. System Configuration
```bash
# Increase R memory limit
echo "options(java.parameters = '-Xmx8g')" >> ~/.Rprofile

# Optimize file descriptors
ulimit -n 4096

# CPU affinity for multi-core
taskset -c 0-3 Rscript R/detect_ipv.R
```

### 2. Application Tuning
```yaml
# config/performance.yml
processing:
  batch_size: 50  # Increase for better throughput
  max_parallel_batches: 8  # Use available cores
  
cache:
  compression: true
  parallel_reads: true
  
logging:
  level: "WARN"  # Reduce logging overhead
  json_format: false  # Text is faster
```

## Troubleshooting

### Common Issues

1. **Memory Errors**
   ```R
   # Increase memory limit
   options(java.parameters = "-Xmx8g")
   memory.limit(size = 16000)  # Windows
   ```

2. **API Rate Limits**
   ```yaml
   # Adjust rate limiting
   api:
     openai:
       rate_limit:
         requests_per_minute: 60  # Reduce if hitting limits
   ```

3. **Connection Timeouts**
   ```yaml
   # Increase timeouts
   api:
     ollama:
       timeout: 600  # 10 minutes for slow models
   ```

### Debug Mode
```bash
# Enable debug logging
export IPVD_LOG_LEVEL=DEBUG

# Run with verbose output
Rscript R/detect_ipv.R -i data/test.xlsx -v

# Check logs
tail -f logs/ipv_detection.log
```

## Production Checklist

- [ ] API keys configured securely
- [ ] Logging configured appropriately
- [ ] Monitoring endpoints accessible
- [ ] Backup strategy implemented
- [ ] Error alerting configured
- [ ] Resource limits set
- [ ] Security scan completed
- [ ] Performance tested
- [ ] Documentation updated
- [ ] Rollback plan ready