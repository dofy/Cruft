#!/bin/bash
#
# Build Cruft and install it to /Applications under a stable local signing
# identity.
#
# Why not just `xcodebuild && cp`: project.yml signs ad-hoc (CODE_SIGN_IDENTITY
# "-"), and TCC cannot pin an ad-hoc signature to anything but the binary's
# cdhash. Granting Full Disk Access then stops working the moment the app is
# rebuilt — the toggle stays on and the row keeps auth_value 2, but every
# request is denied, so the app reports "no file access" and quitting and
# reopening changes nothing. Signing with a self-signed certificate makes TCC
# pin the certificate instead, so the grant survives rebuilds.
#
# Usage: ./Scripts/install-local.sh

set -euo pipefail

readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly derived_data="${TMPDIR%/}/cruft-local/DerivedData"
readonly app_name="Cruft.app"
readonly built_app="$derived_data/Build/Products/Release/$app_name"
readonly installed_app="/Applications/$app_name"
readonly signing_identity="Cruft Local Development"
readonly login_keychain="$HOME/Library/Keychains/login.keychain-db"

ensure_signing_identity() {
    if security find-certificate -c "$signing_identity" "$login_keychain" >/dev/null 2>&1; then
        return
    fi

    (
        local temporary_directory
        local pkcs12_password
        local pkcs12_legacy
        temporary_directory="$(mktemp -d)"
        pkcs12_password="$(openssl rand -hex 24)"
        trap 'rm -rf -- "$temporary_directory"' EXIT

        # OpenSSL 3 defaults PKCS#12 to AES/PBKDF2, which `security import`
        # rejects, so it needs -legacy. The openssl shipped with macOS is
        # LibreSSL, which already writes the older algorithms and has no
        # -legacy option at all — passing it there aborts with a usage dump.
        # Probe instead of assuming which one is on PATH.
        pkcs12_legacy=()
        if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
            pkcs12_legacy=(-legacy)
        fi

        openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
            -subj "/CN=$signing_identity/O=Local Development" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=codeSigning" \
            -keyout "$temporary_directory/private-key.pem" \
            -out "$temporary_directory/certificate.pem" >/dev/null 2>&1

        openssl pkcs12 -export ${pkcs12_legacy[@]+"${pkcs12_legacy[@]}"} \
            -inkey "$temporary_directory/private-key.pem" \
            -in "$temporary_directory/certificate.pem" \
            -name "$signing_identity" \
            -passout "pass:$pkcs12_password" \
            -out "$temporary_directory/identity.p12"

        security import "$temporary_directory/identity.p12" \
            -k "$login_keychain" \
            -P "$pkcs12_password" \
            -T /usr/bin/codesign \
            -T /usr/bin/security >/dev/null
    )
}

ensure_signing_identity

cd "$project_root"
xcodegen generate

# Signing is disabled during the build and done explicitly below, so the
# ad-hoc identity in project.yml does not end up in the installed copy.
xcodebuild \
    -project Cruft.xcodeproj \
    -scheme Cruft \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

codesign --force --deep --sign "$signing_identity" \
    --identifier xyz.phpz.app.cruft \
    "$built_app"
codesign --verify --deep --strict --verbose=2 "$built_app"

pkill -x Cruft 2>/dev/null || true
ditto "$built_app" "$installed_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f -R -trusted "$installed_app"

codesign --verify --deep --strict --verbose=2 "$installed_app"
# No `open -n`: that forces a second instance, so a failed pkill above would
# leave two Cruft processes running.
open "$installed_app"
