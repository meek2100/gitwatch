#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# This file must be run from the root of the repository
# (where the Dockerfile is)

# --- Global Setup & Teardown ---

setup_file() {
    # 1. Build the Docker image from the local Dockerfile
    run docker build -t gitwatch:test .
    assert_success "Docker image build failed"

    # 2. Create a temporary host directory to act as the "watched" volume
    TEST_REPO_DIR=$(mktemp -d)
    export TEST_REPO_DIR
    echo "# DEBUG: Host repo volume created at: $TEST_REPO_DIR" >&3

    # 3. Initialize it as a bare-minimum Git repo
    git -C "$TEST_REPO_DIR" init -q
    git -C "$TEST_REPO_DIR" config user.email "docker-test@example.com"
    git -C "$TEST_REPO_DIR" config user.name "Docker Test"
    touch "$TEST_REPO_DIR/initial_file.txt"
    git -C "$TEST_REPO_DIR" add .
    git -C "$TEST_REPO_DIR" commit -q -m "Initial commit"

    # 4. Get the host runner's UID/GID for the PUID/PGID test
    HOST_UID=$(id -u)
    HOST_GID=$(id -g)
    export HOST_UID
    export HOST_GID
    echo "# DEBUG: Host runner UID/GID: $HOST_UID/$HOST_GID" >&3
}

teardown_file() {
    # 1. Remove the test Docker image
    docker rmi gitwatch:test >/dev/null 2>&1 || true

    # 2. Remove the host repo volume
    if [ -n "$TEST_REPO_DIR" ]; then
        rm -rf "$TEST_REPO_DIR"
        echo "# DEBUG: Cleaned up host repo volume: $TEST_REPO_DIR" >&3
    fi
}

# --- Per-Test Setup & Teardown ---

setup() {
    # Create a unique container name for each test
    CONTAINER_NAME="gitwatch-test-${BATS_TEST_NUMBER}"
    export CONTAINER_NAME
}

teardown() {
    # 1. Dump logs for debugging failures
    echo "# DEBUG: --- Logs for container '$CONTAINER_NAME' ---" >&3
    docker logs "$CONTAINER_NAME" >&3
    echo "# DEBUG: --- End logs for '$CONTAINER_NAME' ---" >&3

    # 2. Stop and remove the container
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

# --- Test Cases ---

@test "docker_puid_gid: Entrypoint correctly switches user" {
    # 1. Run the container with PUID/PGID set to the host user
    run docker run -d --name "$CONTAINER_NAME" \
        -e PUID="$HOST_UID" \
        -e PGID="$HOST_GID" \
        -v "$TEST_REPO_DIR":/app/watched-repo \
        gitwatch:test
    assert_success "Container failed to start"

    # 2. Give the container time to start
    sleep 5

    # 3. Have the container (running as 'appuser') create a file in the volume
    run docker exec "$CONTAINER_NAME" touch /app/watched-repo/puid_test_file.txt
    assert_success "docker exec 'touch' command failed"

    # 4. Assert: Check the ownership of the new file *on the host*.
    # This is the definitive test: if PUID/PGID switching worked,
    # the host user ($HOST_UID/$HOST_GID) should own the file.
    run stat -c "%u %g" "$TEST_REPO_DIR/puid_test_file.txt"
    assert_output "$HOST_UID $HOST_GID"
}

@test "docker_env_vars: Entrypoint correctly passes flags" {
    # 1. Run the container with multiple env vars set
    run docker run -d --name "$CONTAINER_NAME" \
        -e VERBOSE=true \
        -e COMMIT_ON_START=true \
        -e EXCLUDE_PATTERN="*.log,tmp/" \
        -v "$TEST_REPO_DIR":/app/watched-repo \
        gitwatch:test
    assert_success "Container failed to start"

    # 2. Give the container time to start and run the -f flag
    sleep 5

    # 3. Assert: Check the container logs
    run docker logs "$CONTAINER_NAME"

    # 4. Check for flags in the entrypoint startup message
    assert_output --partial "Starting gitwatch with the following arguments:"
    assert_output --partial " -v " # VERBOSE=true -> -v
    assert_output --partial " -f " # COMMIT_ON_START=true -> -f
    # Check that the EXCLUDE_PATTERN was passed to -X (with %q quoting)
    assert_output --partial " -X '*.log,tmp/' "

    # 5. Check for verbose output from gitwatch.sh, proving the flags were received
    # This proves -f was received and processed
    assert_output --partial "Performing initial commit check..."
    # This proves -v was received AND -X was received and processed
    assert_output --partial "Converting glob exclude pattern '.*\.log|tmp/'"
}

@test "docker_env_vars: COMMIT_CMD overrides default message" {
    local custom_message="Custom Docker Commit"

    # 1. Run the container with COMMIT_CMD and a short sleep time
    run docker run -d --name "$CONTAINER_NAME" \
        -e COMMIT_CMD="echo '$custom_message'" \
        -e SLEEP_TIME=1 \
        -v "$TEST_REPO_DIR":/app/watched-repo \
        gitwatch:test
    assert_success "Container failed to start"

    # 2. Wait for the container to initialize
    sleep 3

    # 3. Trigger a change on the host to make gitwatch commit
    touch "$TEST_REPO_DIR/file_for_commit_cmd.txt"

    # 4. Wait for debounce (1s) + commit time
    sleep 3

    # 5. Assert: Check the git log *on the host*
    run git -C "$TEST_REPO_DIR" log -1 --pretty=%B
    assert_output "$custom_message"
}
