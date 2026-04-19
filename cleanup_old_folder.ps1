# Run this script AFTER closing VS Code to remove the old nfc_wallet_app folder
$oldPath = "c:\Users\phamt\project\my_wallet\nfc_wallet_app"
if (Test-Path $oldPath) {
    Remove-Item -Force -Recurse $oldPath
    Write-Host "Deleted $oldPath"
} else {
    Write-Host "Already gone."
}
