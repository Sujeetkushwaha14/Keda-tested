# # Variables
# $SA_NAME="kedastoragesujeet"     # Storage account
# $QUEUE_NAME="keda-queue"         # Queue name
# $MESSAGE="test-message"          # Jo message bhejna hai

# # Send message to queue
# az storage message put `
#   --account-name $SA_NAME `
#   --queue-name $QUEUE_NAME `
#   --content $MESSAGE


# -----------------------------
# Configurable variables
# -----------------------------
$SA_NAME = "kedastoragesujeet"   # Storage account name
$QUEUE_NAME = "keda-queue"       # Queue name
$MESSAGE_COUNT = 100             # Number of messages to push
$MESSAGE_PREFIX = "test-message" # Message content prefix

# -----------------------------
# Push messages to Azure Queue
# -----------------------------
Write-Host "Pushing $MESSAGE_COUNT messages to queue '$QUEUE_NAME'..."
for ($i = 1; $i -le $MESSAGE_COUNT; $i++) {
    $msg = "$MESSAGE_PREFIX-$i"
    az storage message put `
        --account-name $SA_NAME `
        --queue-name $QUEUE_NAME `
        --content $msg `
        --auth-mode login | Out-Null
    Write-Host "Message '$msg' pushed"
}

Write-Host "All messages pushed successfully!"
