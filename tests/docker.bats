#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'

# --- GLOBAL VARS ---
export DOCKER_IMAGE_NAME="gitwatch-test-image"
export DOCKER_CONTAINER_NAME_PREFIX="gitwatch-test"
export TEST_REPO_HOST_DIR="" # Set in setup
export RUNNER_UID=""
export RUNNER_GID=""
# ---------------------

setup_file() {
  # Build the Docker image from the parent directory
  # shellcheck disable=SC2154 # BATS_TEST_DIRNAME is set by BATS
  local repo_root="${BATS_TEST_DIRNAME}/.."

  run docker build -t "$DOCKER_IMAGE_NAME" "$repo_root"

  if [ "$status" -ne 0 ]; then
    echo "# DEBUG: Docker image build failed"
    echo "$output"
  fi
  assert_success "Docker image build failed"
}

teardown_file() {
  # Clean up the Docker image
  docker rmi "$DOCKER_IMAGE_NAME" 2>/dev/null || true
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

# Helper to run a container and wait for it to be ready
run_container() {
  local container_name="$1"
  shift
  local docker_args=( "$@" ) # The rest are docker args

  # Run the container in detached mode
  docker run -d \
    --name "$container_name" \
    --cap-add=SETGID \
    --cap-add=SETUID \
    -v "$TEST_REPO_HOST_DIR:/app/watched-repo" \
    "${docker_args[@]}" \
    "$DOCKER_IMAGE_NAME"

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
  run_container "$container_name" \
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
  run_container "$container_name" \
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

  run_container "$container_name" \
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
