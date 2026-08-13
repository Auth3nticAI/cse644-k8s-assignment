#!/usr/bin/env bash
# Pre-publish safety net for the assignment's Security Rules: scan the whole
# tree for credential-shaped strings before pushing to GitHub. The one
# expected/allowed hit is the deliberately-dummy value in
# k8s/13-python-secret.yaml, which this script explicitly excludes.
#
# Exits non-zero if anything suspicious is found.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

echo "Scanning $REPO_ROOT for credentials..."
echo

HITS=0

report() {  # report <label> <grep-output>
  if [ -n "$2" ]; then
    echo "!! POTENTIAL $1"
    echo "$2" | sed 's/^/     /'
    echo
    HITS=1
  else
    echo "   ok - no $1"
  fi
}

report "kubeconfig-shaped content (a real cluster credential)" \
  "$(grep -rInE 'client-certificate-data|client-key-data|certificate-authority-data' . 2>/dev/null | grep -v 'secret-scan.sh')"

report "Docker Hub access token" \
  "$(grep -rInE 'dckr_pat_[A-Za-z0-9_-]+' . 2>/dev/null | grep -v 'secret-scan.sh')"

report "GitHub token" \
  "$(grep -rInE 'gh[pousr]_[A-Za-z0-9]{20,}' . 2>/dev/null | grep -v 'secret-scan.sh')"

report "AWS access key id" \
  "$(grep -rInE 'AKIA[0-9A-Z]{16}' . 2>/dev/null | grep -v 'secret-scan.sh')"

report "private key block" \
  "$(grep -rInE 'BEGIN (RSA|OPENSSH|EC|DSA|PGP)? ?PRIVATE KEY' . 2>/dev/null | grep -v 'secret-scan.sh')"

report "assigned password/token literal (excluding the assignment's own dummy Secret)" \
  "$(grep -rInE '(password|passwd|api[_-]?key|access[_-]?token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}' . 2>/dev/null \
     | grep -v 'secret-scan.sh' | grep -v '13-python-secret.yaml' | grep -v 'README.md' \
     | grep -viE '(--password-stdin|password prompt|your password|the password)')"

echo
echo "--- credential files that must not be committed ---"
FOUND_FILES="$(find . -type f \( -name '.env' -o -name '*.pem' -o -name '*.key' \
                 -o -name '*.p12' -o -name 'credentials' -o -name 'kubeconfig*' \) \
                 -not -path './.git/*' 2>/dev/null)"
report "credential file" "$FOUND_FILES"

echo
if [ $HITS -eq 0 ]; then
  echo "==================================================="
  echo " CLEAN - no credentials detected. Safe to publish."
  echo "==================================================="
else
  echo "==================================================="
  echo " STOP - review the findings above before pushing."
  echo "==================================================="
fi
exit $HITS
