#!/usr/bin/env bash
# Writes android/rekindle.jks and android/keystore.properties from the signing
# secrets, then checks them with keytool so a wrong secret fails here with a
# specific message instead of deep inside Gradle. Never prints a secret.
#
# Environment: KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD
# Run from the repository root. Needs base64, sha256sum and keytool (JDK).
set -euo pipefail

for var in KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
  if [ -z "${!var:-}" ]; then
    echo "::error::$var is not set; add it under the repository's Settings → Actions → Secrets."
    exit 1
  fi
done

# Values pasted into a web form can pick up line breaks or spaces. They are
# never part of base64 data, and a password can't contain a line break.
keystore_b64=$(printf '%s' "$KEYSTORE_BASE64" | tr -d ' \t\r\n')
store_pass=$(printf '%s' "$KEYSTORE_PASSWORD" | tr -d '\r\n')
# shellcheck disable=SC2153 # KEY_ALIAS is an input variable, not a typo of key_alias
key_alias=$(printf '%s' "$KEY_ALIAS" | tr -d '\r\n')
key_pass=$(printf '%s' "$KEY_PASSWORD" | tr -d '\r\n')

for pair in "KEYSTORE_PASSWORD:$store_pass" "KEY_ALIAS:$key_alias" "KEY_PASSWORD:$key_pass"; do
  name=${pair%%:*}
  value=${pair#*:}
  if [ "$value" != "${value#[[:space:]]}" ] || [ "$value" != "${value%[[:space:]]}" ]; then
    echo "::warning::$name starts or ends with a space; check it wasn't pasted by accident."
  fi
done

if ! printf '%s' "$keystore_b64" | base64 -d > android/rekindle.jks 2>/dev/null; then
  echo "::error::KEYSTORE_BASE64 is not valid base64."
  exit 1
fi
# The keystore is encrypted, so its hash reveals nothing secret. Compare it
# with `sha256sum` of your local keystore to confirm the right file was used.
echo "Keystore: $(stat -c %s android/rekindle.jks) bytes, sha256 $(sha256sum android/rekindle.jks | cut -d' ' -f1)"

# printf writes every value verbatim; an unquoted heredoc would let the shell
# expand $, ` and \ inside a password.
{
  printf 'storeFile=rekindle.jks\n'
  printf 'storePassword=%s\n' "$store_pass"
  printf 'keyAlias=%s\n' "$key_alias"
  printf 'keyPassword=%s\n' "$key_pass"
} > android/keystore.properties

export STORE_PASS="$store_pass" KEY_PASS="$key_pass"

if ! out=$(keytool -list -keystore android/rekindle.jks -storepass:env STORE_PASS 2>&1); then
  case "$out" in
    *"password was incorrect"*|*"keystore password"*)
      echo "::error::KEYSTORE_PASSWORD does not open the keystore in KEYSTORE_BASE64. Either the password is wrong or KEYSTORE_BASE64 encodes a different keystore (compare the sha256 above)." ;;
    *"format"*|*"Invalid"*|*"not a"*)
      echo "::error::KEYSTORE_BASE64 does not decode to a keystore (JKS or PKCS12)." ;;
    *)
      echo "::error::keytool could not read the keystore: $(printf '%s' "$out" | head -1)" ;;
  esac
  exit 1
fi

if ! keytool -list -keystore android/rekindle.jks -storepass:env STORE_PASS -alias "$key_alias" >/dev/null 2>&1; then
  echo "::error::KEY_ALIAS is not an entry in the keystore."
  exit 1
fi

store_type=$(keytool -list -keystore android/rekindle.jks -storepass:env STORE_PASS 2>/dev/null \
  | sed -n 's/^Keystore type: *//p')
echo "Keystore type: ${store_type:-unknown}"

if [ "$store_type" = "PKCS12" ]; then
  # PKCS12 keystores (keytool's default since Java 9) protect the key with the
  # store password, and keytool ignores a separate key password for them, so
  # compare the two instead of testing the key password.
  if [ "$key_pass" != "$store_pass" ]; then
    echo "::error::This is a PKCS12 keystore, whose key password is its store password, but KEY_PASSWORD differs from KEYSTORE_PASSWORD."
    exit 1
  fi
elif ! keytool -certreq -keystore android/rekindle.jks -storepass:env STORE_PASS \
       -alias "$key_alias" -keypass:env KEY_PASS -file /dev/null >/dev/null 2>&1; then
  # certreq needs the private key, so it proves KEY_PASSWORD unlocks it.
  echo "::error::KEY_PASSWORD does not unlock the key KEY_ALIAS."
  exit 1
fi

echo "Keystore, alias and both passwords check out."
