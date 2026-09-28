#!/bin/bash
#
# Package Cruft as a DMG that can be handed to someone else.
#
# The app is not sandboxed and needs Full Disk Access, so it can never ship on
# the Mac App Store. That leaves two options: a Developer ID signature with
# notarization, or a self-signed one. This script does the second by default and
# accepts the first through SIGNING_IDENTITY, because the DMG layout, the
# universal build and the verification steps are the same either way.
#
# Why a self-signed certificate rather than the ad-hoc identity in project.yml:
# TCC pins an ad-hoc signature to the binary's cdhash, so Full Disk Access stops
# working the moment a new build replaces the old one — the toggle stays on, the
# row keeps auth_value 2, and every request is still denied. A certificate makes
# TCC pin the certificate instead, so the grant survives updates as long as every
# build is signed by the same one. Keep the certificate; see the note printed at
# the end.
#
# Usage:
#   ./Scripts/package-release.sh
#   SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" ./Scripts/package-release.sh

set -euo pipefail

readonly project_root="$(cd "$(dirname "$0")/.." && pwd)"
readonly app_name="Cruft.app"
readonly bundle_identifier="xyz.phpz.app.cruft"
readonly derived_data="${TMPDIR%/}/cruft-package/DerivedData"
readonly built_app="$derived_data/Build/Products/Release/$app_name"
readonly login_keychain="$HOME/Library/Keychains/login.keychain-db"
readonly default_identity="Cruft Distribution"
readonly signing_identity="${SIGNING_IDENTITY:-$default_identity}"

# A Developer ID signature needs a secure timestamp and the hardened runtime, or
# notarization rejects it. A self-signed one needs neither, and the timestamp
# server call would only make the build require a network.
if [[ "$signing_identity" == "$default_identity" ]]; then
    readonly signing_options=(--timestamp=none)
    readonly is_self_signed=true
else
    readonly signing_options=(--timestamp --options runtime)
    readonly is_self_signed=false
fi

# stderr, not stdout: build_dmg's result is read through a command substitution,
# so anything this writes to stdout would be appended to the path it returns.
log() {
    printf '\n==> %s\n' "$1" >&2
}

# Reads MARKETING_VERSION out of project.yml so the DMG name and the volume name
# cannot drift from the version the app reports about itself.
read_marketing_version() {
    local version
    version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' \
        "$project_root/project.yml" | head -1)"

    if [[ -z "$version" ]]; then
        echo "error: could not read MARKETING_VERSION from project.yml" >&2
        exit 1
    fi

    printf '%s' "$version"
}

ensure_signing_identity() {
    if [[ "$is_self_signed" == false ]]; then
        if ! security find-identity -v -p codesigning | grep -qF "$signing_identity"; then
            echo "error: no codesigning identity named '$signing_identity' in the keychain" >&2
            exit 1
        fi
        return
    fi

    if security find-certificate -c "$signing_identity" "$login_keychain" >/dev/null 2>&1; then
        return
    fi

    log "Creating the self-signed certificate '$signing_identity'"
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
            -subj "/CN=$signing_identity/O=Cruft" \
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

# ARCHS already resolves to "arm64 x86_64" for the Release configuration, and the
# build still produces an arm64-only binary, which would leave every Intel Mac
# unable to open the app. Force both slices and check the result rather than
# trusting the resolved setting.
build_universal_app() {
    log "Building $app_name (Release, universal)"
    rm -rf "$derived_data"

    xcodegen generate

    # Signing happens explicitly below, so the ad-hoc identity in project.yml
    # never reaches the packaged copy.
    xcodebuild \
        -project Cruft.xcodeproj \
        -scheme Cruft \
        -configuration Release \
        -derivedDataPath "$derived_data" \
        ARCHS="x86_64 arm64" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO \
        build

    local architectures
    architectures="$(lipo -archs "$built_app/Contents/MacOS/Cruft")"
    for architecture in x86_64 arm64; do
        if [[ " $architectures " != *" $architecture "* ]]; then
            echo "error: the binary is missing the $architecture slice (got: $architectures)" >&2
            exit 1
        fi
    done
    log "Architectures: $architectures"
}

sign_app() {
    log "Signing with '$signing_identity'"
    codesign --force --deep --sign "$signing_identity" \
        --identifier "$bundle_identifier" \
        "${signing_options[@]}" \
        "$built_app"
    codesign --verify --deep --strict --verbose=2 "$built_app"
}

write_first_run_note() {
    # macOS quarantines anything that arrives over a download, AirDrop or a
    # messaging app. For a build that Apple has not notarized, Gatekeeper then
    # refuses it outright, and on macOS 15 and later the old right-click-Open
    # shortcut no longer clears it — the only route is Privacy & Security.
    # Without this file the app looks broken rather than unapproved.
    cat > "$1" <<'NOTE'
Cruft — opening it the first time
=================================

This build is signed, but not notarized by Apple, so macOS blocks it until you
approve it once.

1. Drag Cruft to the Applications folder in this window.
2. Open it. macOS will say it cannot verify the developer.
3. Open System Settings > Privacy & Security, scroll to Security, and click
   "Open Anyway" next to Cruft.
4. Open Cruft again and confirm.

Cruft then asks for Full Disk Access, because macOS protects app data, logs,
Downloads, Desktop and the Trash separately. Grant it in
System Settings > Privacy & Security > Full Disk Access.

Every deletion goes to the Trash and nothing is selected without you confirming
it.


Cruft — 第一次打开
==================

这个版本有签名，但没有经过 Apple 公证，所以 macOS 会先拦一次。

1. 把 Cruft 拖到这个窗口里的「应用程序」文件夹。
2. 打开它。macOS 会提示无法验证开发者。
3. 打开「系统设置 > 隐私与安全性」，滚到「安全性」，点 Cruft 旁边的「仍要打开」。
4. 再次打开 Cruft 并确认。

之后 Cruft 会申请「完全磁盘访问权限」，因为 macOS 把应用数据、日志、下载、桌面
和废纸篓分开保护。在「系统设置 > 隐私与安全性 > 完全磁盘访问权限」里授权。

所有删除都进废纸篓，并且任何一项都要你自己确认才会被选中。


Cruft — 第一次打開
==================

這個版本有簽名，但沒有經過 Apple 公證，所以 macOS 會先擋一次。

1. 把 Cruft 拖到這個視窗裡的「應用程式」檔案夾。
2. 開啟它。macOS 會提示無法驗證開發者。
3. 開啟「系統設定 > 隱私權與安全性」，滾到「安全性」，點 Cruft 旁邊的「仍要打開」。
4. 再次開啟 Cruft 並確認。

之後 Cruft 會申請「完全磁碟取用權」，因為 macOS 把應用程式資料、記錄、下載、桌面
和垃圾桶分開保護。在「系統設定 > 隱私權與安全性 > 完全磁碟取用權」裡授權。

所有刪除都進垃圾桶，而且任何一項都要你自己確認才會被選取。
NOTE
}

build_dmg() {
    local version="$1"
    local output_directory="$project_root/dist"
    local dmg_path="$output_directory/Cruft-$version.dmg"
    local staging_directory

    log "Building $(basename "$dmg_path")"
    staging_directory="$(mktemp -d)"
    trap 'rm -rf -- "$staging_directory"' RETURN

    ditto "$built_app" "$staging_directory/$app_name"
    ln -s /Applications "$staging_directory/Applications"
    write_first_run_note "$staging_directory/READ ME FIRST.txt"

    mkdir -p "$output_directory"
    rm -f "$dmg_path"

    # HFS+ rather than APFS: an APFS image will not mount on macOS versions
    # older than the one that wrote it, and the app itself runs on macOS 14.
    hdiutil create \
        -volname "Cruft $version" \
        -srcfolder "$staging_directory" \
        -fs HFS+ \
        -format UDZO \
        -quiet \
        "$dmg_path"

    codesign --force --sign "$signing_identity" "${signing_options[@]}" "$dmg_path"

    printf '%s' "$dmg_path"
}

main() {
    cd "$project_root"

    local version
    version="$(read_marketing_version)"

    ensure_signing_identity
    build_universal_app
    sign_app

    local dmg_path
    dmg_path="$(build_dmg "$version")"

    log "Done"
    printf '  %s\n' "$dmg_path"
    printf '  %s\n' "$(du -h "$dmg_path" | cut -f1)"
    shasum -a 256 "$dmg_path" | awk '{printf "  sha256 %s\n", $1}'

    if [[ "$is_self_signed" == true ]]; then
        cat <<NOTE

  Signed by the self-signed certificate '$signing_identity'.

  Back that certificate up, and sign every future build with it. If it is lost,
  new builds get a different certificate, macOS stops recognising them as the
  same app, and everyone has to grant Full Disk Access again:

    security export -k "$login_keychain" -t identities -f pkcs12 \\
        -o cruft-distribution.p12

  Recipients have to approve the app once in System Settings; "READ ME FIRST.txt"
  inside the DMG walks them through it. A Developer ID certificate plus
  notarization removes that step — pass it as SIGNING_IDENTITY once you have one.
NOTE
    fi
}

main "$@"
