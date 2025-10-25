#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

load startup-shutdown

function pulling_and_rebasing_correctly { #@test

    # --- NOTE: Initial commit is now handled by startup-shutdown.bash ---

    # Start up gitwatch and see if commit and push happen automatically
    # after waiting two seconds
    ${BATS_TEST_DIRNAME}/../gitwatch.sh -v -r origin -R "$testdir/local/remote" 3>- &
    GITWATCH_PID=$!
    # Keeps kill message from printing to screen
    disown

    # Move into the cloned local repository
    cd remote # This cd assumes the clone was named 'remote' inside 'local'

    # According to inotify documentation, a race condition results if you write
    # to directory too soon after it has been created;
    # hence, a short wait.
    sleep 1
    echo "line1" >> file1.txt

    # Wait a bit for inotify to figure out the file has changed, and do its add,
    # commit, and push.
    sleep $WAITTIME

    # Verify that push happened
    currentcommit=$(git rev-parse master)
    remotecommit=$(git rev-parse origin/master)
    [ "$currentcommit" = "$remotecommit" ]

    # Create a second local clone to simulate another user pushing
    cd ../.. # Back to $testdir
    mkdir local2
    cd local2
    git clone -q ../remote # Clone the remote repo again
    cd remote

    # Add a file to the new repo (local2's copy) and push it
    sleep 1
    echo "line2" >> file2.txt
    git add file2.txt
    git commit -q -m "file 2 added" # Commit quietly
    git push -q # Push quietly

    # Change back to original repo (local1's copy), make a third change,
    # gitwatch should pull the change from local2 before pushing
    cd ../../local/remote
    sleep 1
    echo "line3" >> file3.txt

    # Wait for gitwatch to detect change, pull, rebase, commit, and push
    sleep $WAITTIME

    # Verify that push happened (local1's master should match remote's master)
    currentcommit=$(git rev-parse master)
    remotecommit=$(git rev-parse origin/master)
    [ "$currentcommit" = "$remotecommit" ]

    # Verify that the file from local2 (file2.txt) is now present due to the pull
    [ -f file2.txt ]

    # Verify that the file created by local1 (file3.txt) is also present
    [ -f file3.txt ]

    # Check git log to ensure commits are ordered correctly after rebase
    run git log --oneline -n 3 # Check the last 3 commits
    # Output should contain "file 2 added" commit BEFORE the commit containing "line3"
    # Ensure the commit message check is robust against variations
    [[ "$output" == *"file 2 added"* ]] # Check if "file 2 added" exists in the log output

    # Check that file1.txt appears in the recent history (associated with its commit)
    run git log --name-status -n 4
    [[ "$output" == *"file1.txt"* ]]

    # Teardown will remove testing directories
    cd /tmp # Change out of test dir before teardown attempts removal
}
