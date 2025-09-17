# Use a Python base image
FROM python:3.9-alpine

# Install system dependencies including bash, jq, curl and Vault CLI
RUN apk add --no-cache bash jq curl wget unzip

# Install Vault CLI
ENV VAULT_VERSION=1.13.3
RUN wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    unzip vault_${VAULT_VERSION}_linux_amd64.zip && \
    mv vault /usr/local/bin/vault && \
    rm vault_${VAULT_VERSION}_linux_amd64.zip

# Set up the working directory
WORKDIR /app

# Copy and install Python requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all the necessary scripts and configuration files
COPY . .