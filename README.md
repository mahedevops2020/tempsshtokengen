🛠️ Token SSH Access Tool

Usage:
  ./TempSSHtokenGen.sh [--expiry <days>]         Create a new token with expiry in days (default: 1)
  ./TempSSHtokenGen.sh --list                    List all active tokens
  ./TempSSHtokenGen.sh --revoke <token>          Revoke a specific token manually
  ./TempSSHtokenGen.sh --help                    Show this help message

Examples:
  ./TempSSHtokenGen.sh                           Create token with 1-day expiry
  ./TempSSHtokenGen.sh --expiry 3                Create token with 3-day expiry
  ./TempSSHtokenGen.sh --list                    Show active tokens
  ./TempSSHtokenGen.sh --revoke abc123ef         Revoke token 'abc123ef'

🔐 All actions are logged in: /home/mgali/tempSSHTokenGen/token_ssh.log
