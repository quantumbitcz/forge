# Podman

## Overview

Podman is a daemonless, rootless container engine developed by Red Hat that provides a Docker-compatible CLI for building, running, and managing OCI containers and pods. Unlike Docker, Podman does not require a privileged daemon process — each container runs as a direct child process of the user's shell, eliminating the single point of failure and security concern that the Docker daemon represents. Podman is the default container engine on RHEL, CentOS Stream, and Fedora, and it is fully compatible with Dockerfiles, Docker Compose files (via Podman Compose or native `podman compose`), and OCI images.

Use Podman when the organization requires rootless containers for security hardening, when Docker's daemon architecture creates operational concerns (daemon crashes affect all running containers), when deploying on RHEL/Fedora where Podman is the native container engine, or when integrating containers with systemd service management (Quadlet). Podman excels in environments where least-privilege principles are paramount — developers can build and run containers without root access, and production containers can run without any privileged process on the host.

Do not use Podman when the team relies heavily on Docker-specific features that Podman does not support (Docker Swarm mode, Docker's built-in networking for MacOS/Windows without a VM). Do not use Podman on MacOS or Windows for production — while Podman Machine provides a VM-based experience similar to Docker Desktop, native Docker or Docker Desktop is more mature on those platforms. Do not use Podman when the CI/CD pipeline is deeply integrated with Docker-specific APIs — while Podman provides Docker CLI compatibility, some edge cases in build behavior and networking differ.

**Podman vs. Docker comparison:**

| Feature | Podman | Docker |
|---------|--------|--------|
| Architecture | Daemonless (fork/exec) | Client/server daemon |
| Rootless | Native, first-class | Supported but bolt-on |
| Systemd integration | Quadlet (native) | Docker service unit |
| Pod concept | Native (like K8s pods) | Not supported |
| Compose support | podman compose / podman-compose | docker compose |
| Swarm mode | Not supported | Built-in |
| Image building | Buildah (integrated) | BuildKit |
| MacOS/Windows | Podman Machine (VM) | Docker Desktop |
| Socket API | Compatible with Docker API | Native Docker API |
| Container process model | Direct child of caller | Child of daemon |
| Image format | OCI native | OCI + Docker format |

## Architecture Patterns

### Rootless Containers

Rootless containers are Podman's defining feature. They run entirely within a user's namespace without requiring root privileges on the host. This eliminates the privilege escalation risk inherent in Docker's daemon model, where the daemon runs as root and any container escape gives root access to the host.

**Running rootless containers:**
```bash
# No sudo required — containers run as the current user
podman run -d --name myapp -p 8080:8080 registry.example.com/myapp:1.2.3

# Verify the container process runs as the current user
ps aux | grep myapp
# Output shows the container process owned by the user, not root

# Rootless containers use user namespaces
podman unshare cat /proc/self/uid_map
# Shows the UID mapping: container root (0) maps to host user UID
```

**Rootless networking:**
```bash
# Rootless containers cannot bind to ports < 1024 by default
# Use sysctl to allow (system-wide):
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80

# Or use port mapping to higher ports:
podman run -d -p 8080:80 nginx:alpine

# Rootless pods use slirp4netns or pasta for networking
# pasta (default on modern Podman) provides better performance
podman run --network pasta -d myapp:latest
```

**Rootless storage configuration (`~/.config/containers/storage.conf`):**
```toml
[storage]
driver = "overlay"
graphroot = "/home/user/.local/share/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
```

### Daemonless Architecture

Podman's daemonless architecture means each `podman run` command forks a new process using `conmon` (container monitor) as the parent process for the container. There is no long-running daemon that manages all containers — each container is independent.

**Implications:**
```bash
# Containers survive user logout (with loginctl enable-linger)
loginctl enable-linger $(whoami)

# Containers managed as individual processes
podman ps
# Each container has its own conmon process

# No daemon restart affects running containers
# (Unlike Docker, where dockerd restart can disrupt containers)

# Socket activation for Docker API compatibility
systemctl --user enable --now podman.socket

# Docker clients can connect to Podman's API socket
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
docker ps  # Uses Docker CLI against Podman backend
```

### Pod Concept

Podman natively supports pods — groups of containers that share network and IPC namespaces, analogous to Kubernetes pods. This enables local development and testing of multi-container pod configurations that will run on Kubernetes in production.

**Creating and managing pods:**
```bash
# Create a pod with published ports
podman pod create --name myapp-pod -p 8080:8080 -p 5432:5432

# Add containers to the pod
podman run -d --pod myapp-pod --name db \
  -e POSTGRES_DB=myapp -e POSTGRES_PASSWORD=secret \
  postgres:17-alpine

podman run -d --pod myapp-pod --name app \
  -e DATABASE_URL=postgresql://localhost:5432/myapp \
  registry.example.com/myapp:1.2.3

# Containers in the pod share localhost networking
# app can reach db at localhost:5432

# List pods and their containers
podman pod ps
podman pod inspect myapp-pod

# Stop/start the entire pod
podman pod stop myapp-pod
podman pod start myapp-pod

# Generate Kubernetes YAML from a pod
podman generate kube myapp-pod > pod.yaml

# Play Kubernetes YAML (deploy K8s manifests locally)
podman kube play pod.yaml
```

The `podman generate kube` and `podman kube play` commands bridge local development and Kubernetes deployment. Developers can prototype multi-container configurations locally with pods, export to Kubernetes YAML, and deploy to a real cluster without manual manifest writing.

### Podman Compose Compatibility

Podman supports Docker Compose files through two mechanisms: the built-in `podman compose` command (which delegates to an external Compose provider) and the standalone `podman-compose` tool.

**Using podman compose (delegating to docker-compose or compose):**
```bash
# podman compose uses the first available backend:
# 1. docker-compose (if installed)
# 2. podman-compose

# Usage is identical to docker compose
podman compose up -d
podman compose ps
podman compose logs -f app
podman compose down
```

**Using podman-compose (Python reimplementation):**
```bash
# Install
pip install podman-compose

# Usage
podman-compose up -d
podman-compose down
```

**Compose file compatibility:**
```yaml
# compose.yml — works with both Docker and Podman
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgresql://db:5432/myapp
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_PASSWORD: secret
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### Quadlet Systemd Integration

Quadlet is Podman's native systemd integration that generates systemd service units from declarative container/pod/volume definitions. It replaces the older `podman generate systemd` command and provides a declarative, maintainable way to manage containers as system services.

**Quadlet unit files (placed in `~/.config/containers/systemd/` for rootless or `/etc/containers/systemd/` for root):**

```ini
# ~/.config/containers/systemd/myapp.container
[Unit]
Description=MyApp API Server
After=network-online.target postgres.service
Requires=postgres.service

[Container]
Image=registry.example.com/myapp:1.2.3
PublishPort=8080:8080
Environment=SPRING_PROFILES_ACTIVE=production
Environment=DATABASE_URL=postgresql://localhost:5432/myapp
Secret=db-password,type=env,target=DB_PASSWORD
Volume=myapp-config.volume:/app/config:ro
HealthCmd=wget --spider -q http://localhost:8080/actuator/health
HealthInterval=30s
HealthTimeout=5s
HealthRetries=3
AutoUpdate=registry

[Service]
Restart=always
TimeoutStartSec=120

[Install]
WantedBy=default.target
```

```ini
# ~/.config/containers/systemd/postgres.container
[Unit]
Description=PostgreSQL Database

[Container]
Image=postgres:17-alpine
PublishPort=5432:5432
Environment=POSTGRES_DB=myapp
Secret=db-password,type=env,target=POSTGRES_PASSWORD
Volume=postgres-data.volume:/var/lib/postgresql/data
HealthCmd=pg_isready -U postgres
HealthInterval=10s

[Service]
Restart=always

[Install]
WantedBy=default.target
```

```ini
# ~/.config/containers/systemd/postgres-data.volume
[Volume]
Label=app=postgres
```

```bash
# Reload systemd to pick up Quadlet files
systemctl --user daemon-reload

# Start services
systemctl --user start myapp

# Check status
systemctl --user status myapp
systemctl --user status postgres

# View logs
journalctl --user -u myapp -f

# Enable auto-start on login
systemctl --user enable myapp
loginctl enable-linger $(whoami)
```

**Auto-update with Quadlet:**
```bash
# Enable auto-update timer (checks for new image versions)
systemctl --user enable --now podman-auto-update.timer

# Manual update check
podman auto-update

# The AutoUpdate=registry directive in the .container file
# tells podman to pull the latest image and restart if changed
```

### Buildah for Image Building

Buildah is the image-building tool integrated into Podman. While Podman's `build` command uses Buildah internally, Buildah also provides a scripted interface for building images without a Dockerfile, which is useful for CI pipelines and complex build scenarios.

```bash
# Build using Dockerfile (standard)
podman build -t myapp:latest .

# Build with Buildah scripting (Dockerfile-free)
container=$(buildah from alpine:3.20)
buildah run $container -- apk add --no-cache python3 py3-pip
buildah copy $container ./app /app
buildah config --workingdir /app $container
buildah config --cmd "python3 main.py" $container
buildah config --user 1001:1001 $container
buildah commit $container myapp:latest

# Multi-platform builds
podman build --platform linux/amd64,linux/arm64 \
  -t registry.example.com/myapp:1.2.3 \
  --manifest myapp:1.2.3 .

podman manifest push myapp:1.2.3 \
  registry.example.com/myapp:1.2.3
```

## Configuration

### Development

Development Podman configuration mirrors Docker workflows with rootless defaults.

```bash
# Install Podman (Fedora/RHEL)
sudo dnf install podman podman-compose

# Install Podman (Ubuntu)
sudo apt install podman

# MacOS via Podman Machine
brew install podman
podman machine init --cpus 4 --memory 8192 --disk-size 100
podman machine start

# Alias docker to podman for compatibility
alias docker=podman

# Run development stack
podman compose up -d
podman compose logs -f app
```

### Production

Production Podman configuration uses Quadlet for systemd integration, rootless execution, and auto-updates.

```bash
# Ensure rootless prerequisites
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/podman.conf

# Enable lingering for rootless user
loginctl enable-linger appuser

# Deploy Quadlet files
cp *.container *.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start myapp

# Enable auto-updates
systemctl --user enable --now podman-auto-update.timer

# Configure registry authentication
podman login registry.example.com
```

## Performance

**Rootless overhead:** Rootless containers add a small overhead due to user namespace mapping and network namespace setup (slirp4netns or pasta). For most workloads, this overhead is negligible (<1% CPU, <50ms startup latency). For network-intensive workloads, use the `pasta` network backend (default on Podman 5+), which provides significantly better throughput than slirp4netns.

**Storage driver:** Podman uses overlayfs by default. On systems without kernel overlayfs support for unprivileged users, it falls back to fuse-overlayfs, which adds I/O overhead. Modern kernels (5.11+) support native rootless overlayfs, eliminating this overhead.

**Startup time:** Podman's daemonless architecture means each `podman run` must initialize container infrastructure (namespaces, cgroups, networking) from scratch, adding ~100-200ms overhead compared to Docker's daemon-cached initialization. For long-running services, this is irrelevant. For CLI tools that run many short-lived containers, consider using `podman machine` or batch operations.

**Image pull performance:** Podman uses the same OCI image format and registry protocol as Docker. Pull performance is identical. Use a local registry mirror for frequently-used base images to reduce pull times.

## Security

**Rootless by default:** Podman's rootless mode means that even if a container escape occurs, the attacker gains access only to the unprivileged user's resources, not root. This is the single most significant security advantage over Docker's default daemon-based model.

**User namespaces:** Rootless Podman maps container UID 0 (root inside the container) to the host user's UID. This means root-inside-container has the same privileges as the unprivileged host user, eliminating privilege escalation via container escape.

**Seccomp and SELinux:** Podman integrates with both seccomp profiles and SELinux policies. On RHEL/Fedora, SELinux is enforced by default, providing mandatory access control that limits container access to host resources even if namespace isolation is bypassed.

```bash
# Verify SELinux is enforcing
getenforce

# Run with custom seccomp profile
podman run --security-opt seccomp=custom-profile.json myapp:latest

# Run with specific SELinux label
podman run --security-opt label=type:container_t myapp:latest
```

**Secret management:**
```bash
# Create a Podman secret
echo "my-db-password" | podman secret create db-password -

# Use in containers
podman run -d --secret db-password \
  -e DB_PASSWORD_FILE=/run/secrets/db-password \
  myapp:latest

# Use in Quadlet files via Secret= directive
```

## Testing

**Container testing:**
```bash
# Verify container runs correctly
podman run --rm myapp:latest --version

# Health check verification
podman run -d --name test-myapp \
  --health-cmd "wget --spider -q http://localhost:8080/health" \
  --health-interval 5s \
  myapp:latest

podman healthcheck run test-myapp
podman inspect test-myapp --format '{{.State.Health.Status}}'

podman rm -f test-myapp
```

**Docker compatibility testing:**
```bash
# Verify Docker Compose compatibility
podman compose config --quiet

# Verify Docker API compatibility
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
docker info    # Should show Podman backend
docker ps      # Should list Podman containers
```

**Quadlet testing:**
```bash
# Validate Quadlet unit files
/usr/libexec/podman/quadlet --dryrun

# Check generated systemd units
systemctl --user cat myapp.service

# Test service lifecycle
systemctl --user start myapp
systemctl --user status myapp
journalctl --user -u myapp --no-pager -n 50
systemctl --user stop myapp
```

## Dos

- Use rootless Podman as the default mode for both development and production — it provides defense-in-depth without any functional limitation for most workloads.
- Use Quadlet for production service management — it provides declarative, systemd-native container lifecycle management.
- Use `podman generate kube` to bridge local development and Kubernetes deployment.
- Use Podman pods for multi-container applications that share networking, mirroring Kubernetes pod semantics.
- Enable `podman-auto-update.timer` for production services with the `AutoUpdate=registry` Quadlet directive.
- Use `loginctl enable-linger` to keep rootless containers running after user logout.
- Use `pasta` network backend for better rootless networking performance.
- Use Podman secrets for sensitive data in both CLI usage and Quadlet files.

## Don'ts

- Do not run Podman with `sudo` unless absolutely necessary — rootless mode is the secure default.
- Do not use `podman generate systemd` for new deployments — it is deprecated in favor of Quadlet.
- Do not assume Docker Compose features work identically — test Compose files with `podman compose` before relying on compatibility.
- Do not use slirp4netns when pasta is available — pasta provides significantly better network performance.
- Do not ignore user namespace configuration — misconfigured `subuid`/`subgid` ranges cause rootless container failures.
- Do not use Podman Machine for production workloads on Linux — it adds unnecessary VM overhead; use native Podman instead.
- Do not skip `loginctl enable-linger` for rootless services — containers will stop when the user session ends.
- Do not use the Docker socket (`/var/run/docker.sock`) emulation for security-sensitive workloads — understand the security implications of socket access.
