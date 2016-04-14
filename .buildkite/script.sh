#!/bin/bash

echo "~~~ :mag: Testing connection to $SUPERCLUSTER_LOGIN_HOST"

# Do the first check with BatchMode=yes (which won't prompt for password access)
SUPERCLUSTER_NAME=$(ssh -oBatchMode=yes "$SUPERCLUSTER_LOGIN_HOST" "echo \"\$(whoami)@\$(hostname)\"")
SSH_TEST_EXIT_STATUS=$?

# If the SSH connection test failed, we should just bail now
if [[ $SSH_TEST_EXIT_STATUS -ne 0 ]]; then
  echo "SSH connection test exited with $SSH_TEST_EXIT_STATUS"
  echo $SUPERCLUSTER_HOSTNAME
  exit $SSH_TEST_EXIT_STATUS
fi

echo "Connection to $SUPERCLUSTER_LOGIN_HOST is all good! ✅"

# Since we did that test, we can use the information we got back to construct a
# nice display name for prompts
SUPERCLUSTER_PROMPT="\033[90m${SUPERCLUSTER_NAME}:$\033[0m"

COMMAND="hostname && sleep 20"

# CHECKOUT_FOLDER=".buildkite/$BUILDKITE_ORGANIZATION_SLUG/$BUILDKITE_PIPELINE_SLUG"

SUPERCLUSTER_CHECKOUT_FOLDER=".buildkite/${BUILDKITE_JOB_ID}"

# The job name is suffixed with the current PID (so if a job is retried with te
# same $BUILDKITE_JOB_ID, when we check job statuses it won't return the
# previous jobs run status)
SUPERCLUSTER_JOB_NAME="buildkite-job-${BUILDKITE_JOB_ID}-$$"

SUPERCLUSTER_BOOTSTRAP_SCRIPT_NAME="buildkite-bootstrap-${BUILDKITE_JOB_ID}.sh"
SUPERCLUSTER_RUNNER_SCRIPT_NAME="buildkite-runner-${BUILDKITE_JOB_ID}.sh"

# The command script will run the desired command from Buildkite within the compute node
SUPERCLUSTER_COMMAND_SCRIPT_NAME="buildkite-exec-${BUILDKITE_JOB_ID}.sh"
SUPERCLUSTER_COMMAND_LOG_NAME="buildkite-output-${BUILDKITE_JOB_ID}.log"
SUPERCLUSTER_EXIT_STATUS_FILE="buildkite-exit-status-${BUILDKITE_JOB_ID}"

read -r -d '' SUPERCLUSTER_COMMAND_SCRIPT << EOM
#!/bin/bash
set -e
if [[ -f "${COMMAND}" ]]; then
  chmod +x "${COMMAND}"
  ./"${COMMAND}"
else
  ${COMMAND}
fi
EOM

# The runner script is what is submitted to the cluster. It will run the
# command script, stream the output, and store the exit status.
read -r -d '' SUPERCLUSTER_RUNNER_SCRIPT << EOM
#!/bin/bash
./${SUPERCLUSTER_COMMAND_SCRIPT_NAME} >"${SUPERCLUSTER_COMMAND_LOG_NAME}" 2>&1
echo \$? > "${SUPERCLUSTER_EXIT_STATUS_FILE}"
EOM

# The bootstrap script is what is run on the remote login node, that prepares
# it for running a buildkite job
cat > $SUPERCLUSTER_BOOTSTRAP_SCRIPT_NAME <<- EOM
echo 'Connection established to "${SUPERCLUSTER_LOGIN_HOST}"'

function run {
  echo -e "${SUPERCLUSTER_PROMPT} \$1"
  eval "\$1"
  EVAL_EXIT_STATUS=\$?

  if [[ \$EVAL_EXIT_STATUS -ne 0 ]]; then
    exit \$EVAL_EXIT_STATUS
  fi
}

echo '~~~ :package: Preparing repository on the login node'

run "rm -rf \"${SUPERCLUSTER_CHECKOUT_FOLDER}\""
run "mkdir -p \"${SUPERCLUSTER_CHECKOUT_FOLDER}\""

export GIT_TERMINAL_PROMPT=0

run "cd \"${SUPERCLUSTER_CHECKOUT_FOLDER}\""
run "git clone -v -- \"${BUILDKITE_REPO}\" ."

cat > "$SUPERCLUSTER_RUNNER_SCRIPT_NAME" <<- BEOM
${SUPERCLUSTER_RUNNER_SCRIPT}
BEOM

chmod +x "$SUPERCLUSTER_RUNNER_SCRIPT_NAME"

cat > "$SUPERCLUSTER_COMMAND_SCRIPT_NAME" <<- BEOM
${SUPERCLUSTER_COMMAND_SCRIPT}
BEOM

chmod +x "$SUPERCLUSTER_COMMAND_SCRIPT_NAME"

echo '~~~ :floppy_disk: Submitting the job to the cluster'
run "sbatch --workdir=\"\$(pwd)\" --job-name=\"${SUPERCLUSTER_JOB_NAME}\" \"${SUPERCLUSTER_RUNNER_SCRIPT_NAME}\""
EOM

echo '~~~ :wrench: Connecting to the login node'

ssh "$SUPERCLUSTER_LOGIN_HOST" "bash -s" < "$SUPERCLUSTER_BOOTSTRAP_SCRIPT_NAME"
SSH_BOOTSTRAP_EXIT_STATUS=$?

# If the bootstrapping process failed, bad things must have happened...
if [[ $SSH_BOOTSTRAP_EXIT_STATUS -ne 0 ]]; then
  exit $SSH_BOOTSTRAP_EXIT_STATUS
fi

echo '~~~ :hourglass: Waiting for super cluster job to start'

# The job status check command will grab the state for the current job (and
# make sure it has no leading or trailing whitespace)
JOB_STATUS_CHECK_COMMAND="sacct --name=\"${SUPERCLUSTER_JOB_NAME}\" --noheader -o \"state\" -X | tr -d ' '"
JOB_STATUS=""
IS_RUNNING=false

# Run in a loop so if for some reason SSH disconnects, it'll retry the wait
# once it's done. The possible states for a slurm job are:

# RUNNING, RESIZING, SUSPENDED, COMPLETED, CANCELLED, FAILED, TIMEOUT, PREEMPTED, BOOT_FAIL or NODE_FAIL
while true; do
  # Grab the current job status
  NEW_JOB_STATUS=$(ssh "$SUPERCLUSTER_LOGIN_HOST" "$JOB_STATUS_CHECK_COMMAND")
  SSH_GET_STATUS_EXIT_STATUS=$?

  if [[ "$NEW_JOB_STATUS" != "" ]]; then
    echo "Status has changed to \"$NEW_JOB_STATUS\""
  fi

  # If the SSH call fails, wait a while and try the loop again
  if [[ $SSH_GET_STATUS_EXIT_STATUS -ne 0 ]]; then
    echo "SSH exited with status $SSH_GET_STATUS_EXIT_STATUS - retrying in 60 seconds..."
    sleep 60
    continue
  fi

  # Oh, it's running now!?
  if [[ "$NEW_JOB_STATUS" == *"RUNNING"* ]] && [[ "$IS_RUNNING" = false ]]; then
    echo "~~~ :runner: Running on super cluster"
    IS_RUNNING=true
  fi

  # If the job IS_RUNNING and the NEW_JOB_STATUS is no longer *"RUNNING"*, then
  # it's done!
  if [[ "$NEW_JOB_STATUS" != *"RUNNING"* ]] && [[ "$IS_RUNNING" = true ]]; then
    echo "~~~ :thumbsup: Finished on super cluster"
    break
  fi

  JOB_STATUS="$NEW_JOB_STATUS"

  # Monitor the status of the job until it changes
  ssh "$SUPERCLUSTER_LOGIN_HOST" "bash -s" << EOM
  while true; do
    THIS_JOB_STATUS=\$($JOB_STATUS_CHECK_COMMAND)
    if [[ "\$THIS_JOB_STATUS" != "" ]] && [[ "\$THIS_JOB_STATUS" != "${JOB_STATUS}" ]]; then
      exit 0
    fi
    sleep 1
  done
EOM
done

echo "~~~ :earth_asia: Downloading logs from login node"

scp "${SUPERCLUSTER_LOGIN_HOST}":"${SUPERCLUSTER_CHECKOUT_FOLDER}/${SUPERCLUSTER_COMMAND_LOG_NAME} ${SUPERCLUSTER_CHECKOUT_FOLDER}/${SUPERCLUSTER_EXIT_STATUS_FILE}" .

echo "--- :notebook_with_decorative_cover: Results from \`$COMMAND\`"

cat "${SUPERCLUSTER_COMMAND_LOG_NAME}"

exit $(cat "${SUPERCLUSTER_EXIT_STATUS_FILE}")
