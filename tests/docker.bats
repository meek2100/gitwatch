#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'

# --- GLOBAL VARS ---
export DOCKER_IMAGE_NAME="gitwatch-test-image"
export DOCKER_HEALTHCHECK_IMAGE_NAME="gitwatch-healthcheck-test-image"
export DOCKER_CONTAINER_NAME_PREFIX="gitwatch-test"
export TEST_REPO_HOST_DIR="" # Set in setup
export RUNNER_UID=""
export RUNNER_GID=""
# ---------------------

setup_file() {
  # Build the Docker image from the parent directory
  # shellcheck disable=SC2154 # BATS_TEST_DIRNAME is set by BATS
  local repo_root="${BATS_TEST_DIRNAME}/.."

  # --- MODIFIED: Read base image from env var ---
  local base_image="${TEST_BASE_IMAGE:-alpine:3.20}"
  verbose_echo "# DEBUG: Building image with base: $base_image"
  run docker build --build-arg "BASE_IMAGE=$base_image" -t "$DOCKER_IMAGE_NAME" "$repo_root"
  # --- END MODIFICATION ---

  if [ "$status" -ne 0 ]; then
    echo "# DEBUG: Docker image build failed"
    echo "$output"
  fi
  assert_success "Docker image build failed"

  # --- NEW: Build the fast-healthcheck image ---
  verbose_echo "# DEBUG: Building fast-healthcheck image..."
  # Create a temporary Dockerfile that uses a fast interval
  cat > "${BATS_TEST_TMPDIR}/Dockerfile.healthcheck" << EOF
FROM ${DOCKER_IMAGE_NAME}
HEALTHCHECK --interval=3s --timeout=2s --start-period=5s --retries=2 \
  CMD test -f /tmp/gitwatch.status && \
      find /tmp -maxdepth 1 -name gitwatch.status -mmin -1 | grep -q . || \
      exit 1
EOF

  run docker build -t "$DOCKER_HEALTHCHECK_IMAGE_NAME" -f "${BATS_TEST_TMPDIR}/Dockerfile.healthcheck" .
  if [ "$status" -ne 0 ]; then
    echo "# DEBUG: Docker healthcheck image build failed"
    echo "$output"
  fi
  assert_success "Healthcheck Docker image build failed"
  # --- END NEW ---
}

teardown_file() {
  # Clean up the Docker images
  docker rmi "$DOCKER_IMAGE_NAME" 2>/dev/null || true
  docker rmi "$DOCKER_HEALTHCHECK_IMAGE_NAME" 2>/dev/null || true
}

setup() {
  # Get the UID/GID of the user running the tests on the host
  RUNNER_UID=$(id -u)
  RUNNER_GID=$(id -g)

  # Create a temporary directory on the *host* to act as the repo volume
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by BATS
  TEST_REPO_HOST_DIR=$(mktemp -d "$BATS_TEST_TMPDIR/docker-host-repo.XXXXX")
  verbose_echo "# DEBUG: Host repo volume created at: $TEST_REPO_HOST_DIR"
  verbose_echo "# DEBUG: Host runner UID/GID: $RUNNER_UID/$RUNNER_GID"

  # Initialize a git repo in the host directory
  git init "$TEST_REPO_HOST_DIR"
  (
    cd "$TEST_REPO_HOST_DIR" || return 1 # <-- SHELLCHECK FIX

    git config user.email "docker@test.com"
    git config user.name "Docker Test"
    echo "initial" > file.txt
    git add .
    git commit -m "Initial commit"
  )
}

teardown() {
  # Stop and remove all containers with the test prefix
  docker ps -a --filter "name=${DOCKER_CONTAINER_NAME_PREFIX}-" --format "{{.ID}}" | xargs -r docker rm -f
  # Clean up the host directory
  if [ -d "$TEST_REPO_HOST_DIR" ]; then
    # We must 'sudo' this because the container might have changed permissions
    sudo rm -rf "$TEST_REPO_HOST_DIR"
    verbose_echo "# DEBUG: Cleaned up host repo volume: $TEST_REPO_HOST_DIR"
  fi
}

# --- NEW: Helper to create a failing mock git ---
create_failing_mock_git() {
  local real_path="$1"
  local dummy_path="$2" # Pass in the full path
  local dummy_dir
  dummy_dir=$(dirname "$dummy_path")
  mkdir -p "$dummy_dir"

  cat > "$dummy_path" << EOF
#!/usr/bin/env bash
# Mock Git script
echo "# MOCK_GIT: Received command: \$@" >&2

if [ "\$1" = "push" ]; then
  echo "# MOCK_GIT: Push command FAILING" >&2
  exit 1 # Always fail the push
else
  # Pass all other commands (commit, rev-parse, etc.) to the real git
  exec $real_path "\$@"
fi
EOF

  chmod +x "$dummy_path"
}

# --- NEW: Helper to wait for a specific health status ---
wait_for_health_status() {
  local container_name="$1"
  local expected_status="$2"
  local max_attempts=10 # Total wait 20s
  local delay=2
  local attempt=1

  while (( attempt <= max_attempts )); do
    run docker inspect --format '{{.State.Health.Status}}' "$container_name"
    assert_success "Docker inspect failed"

    if [ "$output" = "$expected_status" ]; then
      verbose_echo "# Health status is '$output' as expected."
      return 0
    fi
    verbose_echo "# Waiting for health status '$expected_status', currently '$output' (Attempt $attempt/$max_attempts)..."
    sleep "$delay"
    (( attempt++ ))
  done

  verbose_echo "# Timeout: Health status did not become '$expected_status'. Final status: '$output'"
  return 1
}


# Helper to run a container and wait for it to be ready
run_container() {
  local container_name="$1"
  shift
  local image_name="$1" # <-- MODIFIED: Accept image name
  shift
  local docker_args=( "$@" ) # The rest are docker args

  # Run the container in detached mode
  docker run -d \
    --name "$container_name" \
    --cap-add=SETGID \
    --cap-add=SETUID \
    -v "$TEST_REPO_HOST_DIR:/app/watched-repo" \
    "${docker_args[@]}" \
    "$image_name"

  # Wait for 5 seconds for it to initialize
  sleep 5
}

# Helper to get container logs
get_container_logs() {
  local container_name="$1"
  verbose_echo "# DEBUG: --- Logs for container '$container_name' ---"
  docker logs "$container_name"
  verbose_echo "# DEBUG: --- End logs for '$container_name' ---"
}

@test "docker_puid_gid: Entrypoint correctly switches user" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-1"
  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e PUID="$RUNNER_UID" \
    -e PGID="$RUNNER_GID"

  # 1. Check who owns the files *inside* the container
  run docker exec "$container_name" ls -ld /app/watched-repo

  assert_success "docker exec 'ls' command failed"
  assert_output --partial "appuser appgroup" "PUID/PGID switch failed: /app/watched-repo not owned by appuser:appgroup"

  # 2. Check if the user can write to the volume as 'appuser'
  run docker exec --user appuser "$container_name" touch /app/watched-repo/test-touch
  assert_success "docker exec 'touch' command failed"
}

@test "docker_env_vars: Entrypoint correctly passes flags" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-2"
  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e VERBOSE=true \
    -e COMMIT_ON_START=true \
    -e EXCLUDE_PATTERN="*.log,tmp/" # Test the -X flag

  # Check the container logs to see the command that was executed
  run get_container_logs "$container_name"

  # Check that the entrypoint translated the env vars to the correct flags
  assert_output --partial "Starting gitwatch with the following arguments:"
  assert_output --partial " -v "
  assert_output --partial " -f "
  # Check that the glob pattern was passed to -X
  assert_output --partial " -X \*.log\,tmp/ "
}

@test "docker_env_vars: COMMIT_CMD overrides default message" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-3"
  local custom_message="Custom Docker Commit"

  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e SLEEP_TIME=1 \
    -e COMMIT_CMD="echo '$custom_message'" # Set a custom commit command

  # Wait for the container to start, then trigger a change
  sleep 2
  echo "docker change" >> "$TEST_REPO_HOST_DIR/file.txt"

  # Wait for the commit (Sleep 1s + commit time)
  sleep 3

  # Check the git log on the *host*
  run git -C "$TEST_REPO_HOST_DIR" log -1 --format=%B
  assert_success
  assert_output "$custom_message"
}

@test "docker_env_vars_advanced: Entrypoint correctly handles QUIET and DISABLE_LOCKING" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-4"

  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e QUIET=true \
    -e DISABLE_LOCKING=true

  # 1. Check the container logs
  local logs
  logs=$(get_container_logs "$container_name")

  # 2. Assert: Logs should NOT contain the startup message (due to QUIET=true)

  # The entrypoint.sh itself still echoes, but gitwatch.sh will be quiet.
  run echo "$logs"
  # Check for the entrypoint message (which still runs)
  assert_output --partial "Starting gitwatch with the following arguments:"
  # Check for the flags
  assert_output --partial " -q "
  assert_output --partial " -n "
  # Check that gitwatch.sh *itself* was quiet
  refute_output --partial "Starting file watch. Command:"

  # 3. Assert: Trigger a change and confirm no log output
  sleep 2
  echo "docker quiet change" >> "$TEST_REPO_HOST_DIR/quiet_file.txt"
  sleep 3 # Wait for commit

  logs=$(get_container_logs "$container_name")
  run echo "$logs"
  # The *only* output should be the entrypoint startup line
  assert_output --partial "Starting gitwatch with the following arguments:"
  refute_output --partial "Change detected:"
  refute_output --partial "Running git commit command:"

  # 4. Assert: The commit *did* happen silently
  run git -C "$TEST_REPO_HOST_DIR" log -1 --format=%B
  assert_success
  assert_output --partial "quiet_file.txt"
}

@test "docker_env_vars_log_line_length: GW_LOG_LINE_LENGTH is respected" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-5"
  local long_line="This is a very long line that should be truncated"
  local truncated_line="This is a " # First 10 chars

  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e SLEEP_TIME=1 \
    -e LOG_DIFF_LINES=10 \
    -e GW_LOG_LINE_LENGTH=10 \
    -e COMMIT_MSG="Changes:" \
    -e DATE_FMT=""

  # 1. Check container logs to ensure -l 10 was passed
  run get_container_logs "$container_name"
  assert_output --partial " -l 10 "
  assert_output --partial "Exporting GW_LOG_LINE_LENGTH=10"

  # 2. Trigger a change
  sleep 2
  echo "$long_line" >> "$TEST_REPO_HOST_DIR/long_line.txt"

  # Wait for the commit (Sleep 1s + commit time)
  sleep 3

  # 3. Check the git log on the *host*
  run git -C "$TEST_REPO_HOST_DIR" log -1 --format=%B
  assert_success "Git log check failed"

  # 4. Assert that the truncated line is present (with the '+' from diff-lines)
  assert_output --partial "+${truncated_line}"

  # 5. Assert that the *full* line is *not* present
  refute_output --partial "+${long_line}"
}

# --- NEW TEST ---
@test "docker_healthcheck: Container becomes unhealthy on cool-down and recovers" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-health"
  local real_git_path
  real_git_path=$(command -v git)
  local mock_git_path="$TEST_REPO_HOST_DIR/mock-bin/git"

  # 1. Create the mock git binary on the host
  create_failing_mock_git "$real_git_path" "$mock_git_path"
  verbose_echo "# DEBUG: Created failing mock git at $mock_git_path"

  # 2. Run the *healthcheck* container
  run_container "$container_name" "$DOCKER_HEALTHCHECK_IMAGE_NAME" \
    -e SLEEP_TIME=1 \
    -e GW_MAX_FAIL_COUNT=2 \
    -e GW_COOL_DOWN_SECONDS=10 \
    -e GIT_REMOTE=origin \
    -e GW_GIT_BIN="/usr/local/bin/git" \
    -v "$mock_git_path:/usr/local/bin/git:ro" # Mount the mock git

  verbose_echo "# DEBUG: Container started. Waiting for 'healthy' status..."

  # 3. Check initial health (should be 'healthy' after start-period)
  run wait_for_health_status "$container_name" "healthy"
  assert_success "Container did not become 'healthy' after starting"

  # 4. Trigger failures (GW_MAX_FAIL_COUNT=2)
  verbose_echo "# DEBUG: Triggering 2 failures..."
  echo "change 1" >> "$TEST_REPO_HOST_DIR/health_file.txt"
  sleep 3 # Wait for commit/push to fail
  echo "change 2" >> "$TEST_REPO_HOST_DIR/health_file.txt"
  sleep 3 # Wait for commit/push to fail

  # 5. Check for 'unhealthy'
  verbose_echo "# DEBUG: Failures triggered. Waiting for 'unhealthy' status..."
  run wait_for_health_status "$container_name" "unhealthy"
  assert_success "Container did not become 'unhealthy' after entering cool-down"

  # 6. Check container logs to confirm cool-down
  run get_container_logs "$container_name"
  assert_output --partial "Incrementing failure count to 1/2"
  assert_output --partial "Incrementing failure count to 2/2"
  assert_output --partial "Max failures reached. Entering cool-down period for 10 seconds."

  # 7. Wait for recovery
  # (10s cool-down + 3s health interval + 3s buffer)
  verbose_echo "# DEBUG: Waiting 16s for cool-down to end and health to recover..."
  sleep 16

  # 8. Check for 'healthy' again
  run wait_for_health_status "$container_name" "healthy"
  assert_success "Container did not return to 'healthy' status after cool-down"

  # 9. Check logs for recovery message
  run get_container_logs "$container_name"
  assert_output --partial "Cool-down period finished. Resetting failure count and retrying."
}
