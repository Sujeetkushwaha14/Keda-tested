$SA_NAME="stoexp25667805699"
$QUEUE_NAME = "demo-queue"

1..100 | ForEach-Object {
  az storage message put `
    --queue-name $QUEUE_NAME `
    --account-name $SA_NAME `
    --content "test-$_" `
    --auth-mode login | Out-Null
}
