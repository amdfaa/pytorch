#!/usr/bin/env bash
set -ex

run_as_root() {
    if [[ "$(id -u)" == 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_docker_packages() {
    if ! command -v apt-get >/dev/null; then
        echo "Docker bootstrap currently supports Ubuntu agents with apt-get" >&2
        exit 1
    fi

    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update

    local python_venv_package
    python_venv_package="$(python3 - <<'PY'
import sys

print(f"python{sys.version_info.major}.{sys.version_info.minor}-venv")
PY
)"

    local buildx_package
    buildx_package=""
    if apt-cache show docker-buildx >/dev/null 2>&1; then
        buildx_package="docker-buildx"
    elif apt-cache show docker-buildx-plugin >/dev/null 2>&1; then
        buildx_package="docker-buildx-plugin"
    else
        echo "No docker buildx package found in apt metadata" >&2
        exit 1
    fi

    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        docker.io \
        "${buildx_package}" \
        fuse-overlayfs \
        "${python_venv_package}"
}

configure_docker_daemon() {
    local daemon_config
    daemon_config="$(mktemp)"
    cat >"${daemon_config}" <<'JSON'
{
  "features": {
    "buildkit": true
  },
  "storage-driver": "fuse-overlayfs"
}
JSON

    run_as_root install -d -m 0755 /etc/docker
    run_as_root install -m 0644 "${daemon_config}" /etc/docker/daemon.json
    rm -f "${daemon_config}"

    local agent_user
    agent_user="${SUDO_USER:-${USER:-}}"
    if [[ -n "${agent_user}" ]] && getent group docker >/dev/null; then
        run_as_root usermod -aG docker "${agent_user}"
    fi
}

docker_storage_driver() {
    run_as_root docker info --format '{{.Driver}}' 2>/dev/null || true
}

stop_docker_daemon_without_systemd() {
    if ! run_as_root docker info >/dev/null 2>&1; then
        return
    fi

    run_as_root sh -c '
if [ -f /var/run/docker.pid ]; then
    kill "$(cat /var/run/docker.pid)" || true
else
    pkill -x dockerd || true
fi
'

    for _ in {1..30}; do
        if ! run_as_root docker info >/dev/null 2>&1; then
            return
        fi
        sleep 1
    done
}

start_docker_daemon() {
    if command -v systemctl >/dev/null && \
        run_as_root systemctl restart docker >/dev/null 2>&1; then
        run_as_root systemctl enable docker >/dev/null 2>&1 || true
    else
        stop_docker_daemon_without_systemd
        run_as_root sh -c '
nohup dockerd --config-file=/etc/docker/daemon.json >/tmp/dockerd.log 2>&1 &
echo $! >/tmp/dockerd.pid
'
    fi

    for _ in {1..30}; do
        if [[ "$(docker_storage_driver)" == "fuse-overlayfs" ]]; then
            run_as_root docker buildx version
            return
        fi
        sleep 1
    done

    echo "Docker daemon did not become ready with fuse-overlayfs storage" >&2
    run_as_root docker info >&2 || true
    if [[ -f /tmp/dockerd.log ]]; then
        run_as_root tail -n 100 /tmp/dockerd.log >&2 || true
    fi
    exit 1
}

install_docker_packages
configure_docker_daemon
start_docker_daemon

grep -qxF "export DOCKER_BUILDKIT=1" ~/.bashrc || \
    echo "export DOCKER_BUILDKIT=1" >> ~/.bashrc
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
uv pip install numpy
lintrunner init
NIGHTLY_PATCH=$(curl -s https://github.com/pytorch/pytorch/commit/nightly.patch | head -n20)
COMMIT=$(grep -oE '[0-9a-f]{40}' <<< "$NIGHTLY_PATCH" | head -1)
COMMIT_DATE=$(echo "$NIGHTLY_PATCH" | grep '^Date:' | sed -E 's/Date: .*, ([0-9]+) ([A-Za-z]+) ([0-9]+) .*/\3 \2 \1/' | awk 'BEGIN{split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", months, " "); for(i=1;i<=12;i++) month[months[i]]=sprintf("%02d",i)} {print $1 month[$2] sprintf("%02d",$3)}')
VERSION_STRING="2.9.0.dev${COMMIT_DATE}+cpu"
git rev-parse HEAD > /tmp/orig_work.txt
git reset --hard $COMMIT
USE_NIGHTLY=$VERSION_STRING python -m pip install --no-build-isolation -v -e .
echo "source $PWD/.venv/bin/activate" >> ~/.bashrc
