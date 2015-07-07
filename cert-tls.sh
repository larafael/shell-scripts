#!/bin/sh

show_usage() {
    echo "Usage: cert-tls [OPTION]... DOMAIN [DOMAIN2]...

Generate a self-signed x.509 certificate for use with SSL/TLS.

Options:
  -o PATH -- output the cert to a file at PATH
  -k PATH -- output the key to a file at PATH
  -K PATH -- sign key at PATH (instead of generating a new one)
  -c CC   -- country code listed in the cert (default: XX)
  -s SIZE -- generate a key of size SIZE (default: 2048)
  -y N    -- expire cert after N years (default: 10)"
}

main() {
    local C SUBJECT_ALT_NAME
    local cert cert_out expires_years is_temp_key key_out key_path key_size opts result
    C=XX
    expires_years=10
    key_size=2048

    local OPTIND
    while getopts ho:k:K:c:s:y: opt; do
        case "$opt" in
            h) show_usage; exit ;;
            o) cert_out="$OPTARG" ;;
            k) key_out="$OPTARG" ;;
            K) key_path="$OPTARG" ;;
            c) C="$OPTARG" ;;
            s) key_size="$OPTARG" ;;
            y) expires_years="$OPTARG" ;;
        esac
    done
    shift $(( OPTIND - 1 ))

    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    opts=$(get_options "$@")
    if [ -n "$opts" ]; then
        die "Error: all options must go at the beginning: $opts"
    fi

    if ! has_command "$OPENSSL"; then
        die "Error: $OPENSSL command not found"
    fi

    SUBJECT_ALT_NAME=$(join_commas $(map_subject "$@"))

    if [ -z "$key_path" ]; then
      is_temp_key=1
      key_path=$(make_tempfile)                             &&
      (umask 077; generate_key "$key_size" >| "$key_path")
    fi                                                      &&

    cert=$(C="$C" \
        CN="$1" \
        SUBJECT_ALT_NAME="$SUBJECT_ALT_NAME" \
        KEY="$key_path" \
        DAYS=$(( 365 * expires_years )) \
        generate_cert)                                      &&

    printf '%s\n' "$cert" | output "$cert_out"              &&
    (umask 077; output "$key_out" < "$key_path")            &&

    if [ -n "$is_temp_key" ]; then
      rm -- "$key_path"
    fi
}

join_commas() {
    (IFS=,; printf '%s\n' "$*")
}

map_subject() {
    local arg
    for arg; do
        printf '%s\n' "DNS:$arg"
    done
}

generate_key() {
    "$OPENSSL" genrsa "$1" 2>/dev/null
}

generate_cert() {
    local cfg
    cfg=$(make_tempfile)                     &&
    printf '%s' "$CONFIG_TEMPLATE" >| "$cfg" &&

    C="$C" CN="$CN" SUBJECT_ALT_NAME="$SUBJECT_ALT_NAME" \
        "$OPENSSL" req \
        -config "$cfg" \
        -days "$DAYS" \
        -key "$KEY" \
        -new \
        -sha256 \
        -utf8 \
        -x509                                &&

    rm -f -- "$cfg"
}

CONFIG_TEMPLATE="[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = \$ENV::C
CN = \$ENV::CN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = \$ENV::SUBJECT_ALT_NAME
"

get_options() {
    local arg
    for arg; do
        case "$arg" in
            -*) printf '%s ' "$arg" ;;
        esac
    done
}

output() {
    if [ -z "$1" ]; then
        cat
    else
        cat >| "$1"
    fi
}

has_command() {
    hash "$1" 2>/dev/null
}

make_tempfile() {
    mktemp -t cert.XXXXXX
}

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

OPENSSL=openssl

main "$@"
