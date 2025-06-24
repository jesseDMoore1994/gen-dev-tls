#!/usr/bin/env bash

set -euo pipefail

# === CONFIGURATION (can be set via environment variables) ===
DAYS="${DAYS:-365}"
CA_CN="${CA_CN:-DevCA}"
SERVER_CN="${SERVER_CN:-localhost}"
CLIENT_CN="${CLIENT_CN:-client}"

usage() {
    echo "Usage: $0 [gen|clean|test] [output_dir]"
    echo "  gen [output_dir]   - Generate development TLS certificates and keys (to output_dir, default: current dir)"
    echo "  clean [output_dir] - Remove generated certificates and keys (from output_dir, default: current dir)"
    echo "  test [output_dir]  - Validate the generated certificates (in output_dir, default: current dir)"
    echo
    echo "You can also override configuration with environment variables:"
    echo "  DAYS       - Validity period (default: 365)"
    echo "  CA_CN      - Certificate Authority Common Name (default: DevCA)"
    echo "  SERVER_CN  - Server certificate Common Name (default: localhost)"
    echo "  CLIENT_CN  - Client certificate Common Name (default: client)"
    exit 1
}

# Helper for file paths (outputs absolute path)
file_path() {
    local name="$1"
    if [[ "$OUTPUT_DIR" = "." ]]; then
        echo "$name"
    else
        echo "${OUTPUT_DIR}/$name"
    fi
}

clean() {
    echo "Cleaning generated certificates and keys in '$OUTPUT_DIR'..."
    rm -f "$(file_path dev-ca.key)" \
          "$(file_path dev-ca.pem)" \
          "$(file_path server.key)" \
          "$(file_path server.crt)" \
          "$(file_path client.key)" \
          "$(file_path client.crt)" \
          "$(file_path dev-ca.srl)" \
          "$(file_path server.log)" \
          "$(file_path client_test.log)" \
          "$(file_path san.cnf)" \
          "$(file_path server.csr)" \
          "$(file_path client.csr)" \
          2>/dev/null || true
    echo "Done."
}

generate() {
    mkdir -p "$OUTPUT_DIR"
    echo "Generating development CA, server, and client certificates in '$OUTPUT_DIR'..."
    echo "  DAYS=${DAYS}"
    echo "  CA_CN=${CA_CN}"
    echo "  SERVER_CN=${SERVER_CN}"
    echo "  CLIENT_CN=${CLIENT_CN}"

    # 1. Create a Certificate Authority (CA)
    openssl genrsa -out "$(file_path dev-ca.key)" 2048
    openssl req -x509 -new -nodes -key "$(file_path dev-ca.key)" -sha256 -days 3650 -out "$(file_path dev-ca.pem)" -subj "/CN=${CA_CN}"

    # 2. Create a Subject Alternative Name (SAN) config
    cat > "$(file_path san.cnf)" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[ req_distinguished_name ]
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF

    # 3. Generate Server Certificate
    openssl genrsa -out "$(file_path server.key)" 2048
    openssl req -new -key "$(file_path server.key)" -out "$(file_path server.csr)" -subj "/CN=${SERVER_CN}" -config "$(file_path san.cnf)"
    openssl x509 -req -in "$(file_path server.csr)" -CA "$(file_path dev-ca.pem)" -CAkey "$(file_path dev-ca.key)" -CAcreateserial -out "$(file_path server.crt)" -days "${DAYS}" -sha256 -extfile "$(file_path san.cnf)" -extensions v3_req

    # 4. Generate Client Certificate
    openssl genrsa -out "$(file_path client.key)" 2048
    openssl req -new -key "$(file_path client.key)" -out "$(file_path client.csr)" -subj "/CN=${CLIENT_CN}"
    openssl x509 -req -in "$(file_path client.csr)" -CA "$(file_path dev-ca.pem)" -CAkey "$(file_path dev-ca.key)" -CAcreateserial -out "$(file_path client.crt)" -days "${DAYS}" -sha256

    # 5. Cleanup
    rm -f "$(file_path server.csr)" "$(file_path client.csr)" "$(file_path san.cnf)" "$(file_path dev-ca.srl)"

    echo "All certificates and keys have been generated in '$OUTPUT_DIR':"
    echo "  Root CA:      dev-ca.pem (cert), dev-ca.key (key)"
    echo "  Server Cert:  server.crt (cert), server.key (key)"
    echo "  Client Cert:  client.crt (cert), client.key (key)"
}

test_certs() {
    PORT=8443
    echo "Testing certificates using openssl s_server and s_client on port $PORT in '$OUTPUT_DIR'..."

    # Start server in background
    openssl s_server \
        -accept $PORT \
        -cert "$(file_path server.crt)" \
        -key "$(file_path server.key)" \
        -CAfile "$(file_path dev-ca.pem)" \
        -Verify 1 \
        -quiet > "$(file_path server.log)" 2>&1 &
    SERVER_PID=$!
    sleep 1

    # Client handshake test
    echo | openssl s_client \
        -connect localhost:$PORT \
        -cert "$(file_path client.crt)" \
        -key "$(file_path client.key)" \
        -CAfile "$(file_path dev-ca.pem)" \
        -quiet > "$(file_path client_test.log)" 2>&1
    CLIENT_RESULT=$?

    # Kill server
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true

    # Check handshake result
    if grep -q "Verify return code: 0 (ok)" "$(file_path client_test.log)"; then
        echo "SUCCESS: Handshake and certificate validation succeeded."
        rm -f "$(file_path client_test.log)"
        exit 0
    else
        echo "ERROR: Handshake or certificate validation failed."
        echo "See $(file_path server.log) and $(file_path client_test.log) for details."
        exit 1
    fi
}

# Parse command and (optional) output_dir argument
if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
fi

COMMAND="$1"
OUTPUT_DIR="${2:-.}"

case "$COMMAND" in
    gen)
        generate
        ;;
    clean)
        clean
        ;;
    test)
        test_certs
        ;;
    *)
        usage
        ;;
esac
