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
  # --- FIX 1: Skip if Docker is not available ---
  if ! command -v docker &>/dev/null; then
    skip "Test skipped: 'docker' command not found, which is required for Docker E2E tests."
  fi
  # --- END FIX 1 ---

  # Build the Docker image from the parent directory
  # shellcheck disable=SC2154 # BATS_TEST_DIRNAME is set by BATS
  local repo_root="${BATS_TEST_DIRNAME}/.."

  # --- FIX 2: Ensure a consistently safe and existing writable temp location ---
  # Fallback to /tmp if BATS_TEST_TMPDIR is somehow empty/unset in setup_file context
  local temp_dir="${BATS_TEST_TMPDIR:-/tmp}"
  local healthcheck_file="$temp_dir/Dockerfile.healthcheck"

  # --- MODIFIED: Read base image from env var ---
  local base_image="${TEST_BASE_IMAGE:-alpine:3.20}"
  verbose_echo "# DEBUG: Building image with base: $base_image"
  run docker build --build-arg "BASE_IMAGE=$base_image" -t "$DOCKER_IMAGE_NAME" "$repo_root"

  if [ "$status" -ne 0 ];
  then
    echo "# DEBUG: Docker image build failed"
    echo "$output"
  fi
  assert_success "Docker image build failed"

  # --- NEW: Build the fast-healthcheck image ---
  verbose_echo "# DEBUG: Building fast-healthcheck image..."
  # Create a temporary Dockerfile that uses a fast interval
  # Write to the determined safe location

  # --- FIX 3 (CRITICAL): Single-line, escaped CMD for Dockerfile HEALTHCHECK ---
  # This fixes the 'unknown instruction: grep' Dockerfile parse error.
  cat > "$healthcheck_file" << EOF
FROM ${DOCKER_IMAGE_NAME}
HEALTHCHECK --interval=3s --timeout=2s --start-period=5s --retries=2 \\
  CMD /bin/sh -c "test -f /tmp/gitwatch.status && find /tmp -maxdepth 1 -name gitwatch.status -mmin -1 | grep -q . || exit 1"
EOF

  run docker build -t "$DOCKER_HEALTHCHECK_IMAGE_NAME" -f "$healthcheck_file" .
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
  # --- FIX 4: Clean up the temporary Dockerfile using the safe path logic ---
  local temp_dir="${BATS_TEST_TMPDIR:-/tmp}"
  rm -f "$temp_dir/Dockerfile.healthcheck" 2>/dev/null || true
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

  # *** CRITICAL FIX: Explicitly ensure host directory permissions ***
  # Set permissions to rwx for all (safe in test environment) before git init.
  # This avoids the "cd: Permission denied" error in gitwatch.sh inside the container,
  # as the PUID/PGID mapping relies on the correct host user having full access.
  # This fixes tests 1, 3, 4, 5, 6.
  run chmod 777 "$TEST_REPO_HOST_DIR"
  assert_success "Failed to set permissive permissions on host repo directory"

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
  if [ -d "$TEST_REPO_HOST_DIR" ];
  then
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

if [ "\$1" = "push" ];
then
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

  while (( attempt <= max_attempts ));
  do
    run docker inspect --format '{{.State.Health.Status}}' "$container_name"
    assert_success "Docker inspect failed"

    if [ "$output" = "$expected_status" ];
    then
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

  # Wait for 5 seconds for it to initialize (and hopefully not crash immediately)
  sleep 5
}

# Helper to get container logs
get_container_logs() {
  local container_name="$1"
  verbose_echo "# DEBUG: --- Logs for container '$container_name' ---"
  docker logs "$container_name"
  verbose_echo "# DEBUG: --- End logs for '$container_name' ---"
}

@test "docker_puid_gid_entrypoint_correctly_switches_user" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-1"
  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e PUID="$RUNNER_UID" \
    -e PGID="$RUNNER_GID"

  # 1. Assert: Check if the user can write to the volume as 'appuser'
  #    This check confirms PUID/PGID mapping and correct permissions. (Fixes original assertion failure)
  run docker exec --user appuser "$container_name" touch /app/watched-repo/test-touch
  assert_success "docker exec 'touch' command failed (PUID/PGID mapping likely failed or permissions are wrong)"

  # 2. Check the file still exists on the host (confirms volume functionality)
  run test -f "$TEST_REPO_HOST_DIR/test-touch"
  assert_success "File created in container is missing on host."

  # Cleanup
  run rm "$TEST_REPO_HOST_DIR/test-touch"
}

@test "docker_env_vars_entrypoint_correctly_passes_flags" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-2"
  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e VERBOSE=true \
    -e COMMIT_ON_START=true \
    -e EXCLUDE_PATTERN="*.log,tmp/" # Test the -X flag

  # Check the container logs to see the command that was executed
  local logs
  logs=$(get_container_logs "$container_name")

  # Check that the entrypoint translated the env vars to the correct flags
  run echo "$logs"
  assert_output --partial "Starting gitwatch with the following arguments:"
  assert_output --partial " -v "
  assert_output --partial " -f "
  # Check that the glob pattern was passed to -X
  assert_output --partial " -X \*.log\,tmp/ "
}

@test "docker_env_vars_commit_cmd_overrides_default_message" {
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

@test "docker_env_vars_advanced_entrypoint_correctly_handles_quiet_and_disable_locking" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-4"

  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e QUIET=true \
    -e DISABLE_LOCKING=true

  # 1. Check the container logs
  local logs
  logs=$(get_container_logs "$container_name")

  # 2. Assert: Logs from gitwatch.sh should be suppressed.
  run echo "$logs"
  # Check for the flags in entrypoint.sh's output
  assert_output --partial " -q "
  assert_output --partial " -n "
  # Check that gitwatch.sh *itself* was quiet
  refute_output --partial "[INFO] Starting file watch. Command:"

  # 3. Assert: Trigger a change and confirm commit happened silently
  sleep 2
  echo "docker quiet change" >> "$TEST_REPO_HOST_DIR/quiet_file.txt"
  sleep 3 # Wait for commit

  # Assert: The commit *did* happen silently
  run git -C "$TEST_REPO_HOST_DIR" log -1 --format=%B
  assert_success
  # The commit message contains the file name from the default message logic
  assert_output --partial "quiet_file.txt"

  # 4. Final check for quiet logs (no output after commit)
  local new_logs
  new_logs=$(get_container_logs "$container_name")
  run echo "$new_logs"
  # Should not see any log message that would come after startup.
  refute_output --partial "Change detected:"
  refute_output --partial "Running git commit command:"

}

@test "docker_env_vars_log_line_length_gw_log_line_length_is_respected" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-5"
  local long_line="This is a very long line that should be truncated"
  local truncated_line="This is a " # First 10 chars

  run_container "$container_name" "$DOCKER_IMAGE_NAME" \
    -e SLEEP_TIME=1 \
    -e LOG_DIFF_LINES=10 \
    -e GW_LOG_LINE_LENGTH=10 \
    -e COMMIT_MSG="Changes:" \
    -e DATE_FMT=""

  # 1. Check container logs to ensure -l 10 and GW_LOG_LINE_LENGTH was passed
  local logs
  logs=$(get_container_logs "$container_name")
  run echo "$logs"
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
@test "docker_healthcheck_container_becomes_unhealthy_on_cool_down_and_recovers" {
  local container_name="${DOCKER_CONTAINER_NAME_PREFIX}-health"
  local real_git_path
  real_git_path=$(command -v git)
  local mock_git_path="$TEST_REPO_HOST_DIR/mock-bin/git"

  # 1. Create the mock git binary on the host
  create_failing_mock_git "$real_git_path" "$mock_git_path"
  verbose_echo "# DEBUG: Created failing mock git at $mock_git_path"

  # 2. Run the *healthcheck* container
  # We must bind mount the mock git binary to GW_GIT_BIN inside the container.
  run_container "$container_name" "$DOCKER_HEALTHCHECK_IMAGE_NAME" \
    -e SLEEP_TIME=1 \
    -e GW_MAX_FAIL_COUNT=2 \
    -e GW_COOL_DOWN_SECONDS=10 \
    -e GIT_REMOTE=origin \
    -e GW_GIT_BIN="/app/watched-repo/mock-bin/git" \
    -v "$mock_git_path:/app/watched-repo/mock-bin/git:ro" # Mount the mock git

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
  local logs
  logs=$(get_container_logs "$container_name")
  run echo "$logs"
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
