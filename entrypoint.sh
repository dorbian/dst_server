#!/usr/bin/env bash
set -euo pipefail

# Required
: "${DST_CLUSTER:?Set DST_CLUSTER (cluster name under /data/DoNotStarveTogether/<cluster>)}"

# Optional
DST_SHARDS="${DST_SHARDS:-Master,Caves}"
MOD_UPDATE_RETRIES="${MOD_UPDATE_RETRIES:-6}"
MOD_UPDATE_BACKOFF_SECONDS="${MOD_UPDATE_BACKOFF_SECONDS:-10}"

DST_BIN="/opt/dst/bin/dontstarve_dedicated_server_nullrenderer"
CLUSTER_DIR="/data/DoNotStarveTogether/${DST_CLUSTER}"

# Steam path expectations (some Steam libs look here)
mkdir -p /steam/Steam/steamapps/workshop/{content,downloads} /steam/Steam/steamapps/common
mkdir -p /home/dst/.steam /home/dst/.local/share
ln -sfn /steam/Steam /home/dst/.steam/steam
ln -sfn /steam/Steam /home/dst/.local/share/Steam

# Make sure cluster structure exists
mkdir -p "${CLUSTER_DIR}/mods"
for shard in ${DST_SHARDS//,/ }; do
  mkdir -p "${CLUSTER_DIR}/${shard}"
done

# Workshop list file (canonical location)
if [[ ! -f "${CLUSTER_DIR}/mods/dedicated_server_mods_setup.lua" ]]; then
  echo "WARN: ${CLUSTER_DIR}/mods/dedicated_server_mods_setup.lua missing."
  echo '      Create it with lines like: ServerModSetup("378160973")'
fi

# Sanity: ensure install exists
if [[ ! -x "${DST_BIN}" ]]; then
  echo "ERROR: DST binary not found at ${DST_BIN}"
  exit 1
fi

# Run mod update once before starting shards (deterministic)
echo "=== Workshop mod sync phase ==="
for attempt in $(seq 1 "${MOD_UPDATE_RETRIES}"); do
  echo "--- attempt ${attempt}/${MOD_UPDATE_RETRIES} ---"
  if "${DST_BIN}" \
      -only_update_server_mods \
      -persistent_storage_root /data \
      -cluster "${DST_CLUSTER}" \
      -shard Master
  then
    echo "Workshop sync succeeded."
    break
  fi

  if [[ "${attempt}" -eq "${MOD_UPDATE_RETRIES}" ]]; then
    echo "ERROR: Workshop sync failed after ${MOD_UPDATE_RETRIES} attempts."
    exit 1
  fi

  sleep $((attempt * MOD_UPDATE_BACKOFF_SECONDS))
done

# Start shards
echo "=== Starting shards: ${DST_SHARDS} ==="
pids=()
for shard in ${DST_SHARDS//,/ }; do
  echo "Starting shard: ${shard}"
  "${DST_BIN}" \
    -persistent_storage_root /data \
    -cluster "${DST_CLUSTER}" \
    -shard "${shard}" &
  pids+=("$!")
done

# Wait: if any shard exits, stop container so restartPolicy can restart it
wait -n "${pids[@]}"
echo "A shard exited; stopping container."
exit 1
