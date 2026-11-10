# Test fixtures excluded from this repository

Some binary test inputs are intentionally **not** committed here because their raw
bytes (e.g. embedded PKCS#7 signature blobs) match generic content-scanner rules used
for publication hygiene. They remain required by certain integration tests.

## `crates/sign/tests/data/openssl-signed.pdf`

A minimal PDF carrying an `adbe.pkcs7.detached` signature, used by
`crates/sign/tests/it/{chain,pdf}.rs`. To run those tests locally, regenerate a
self-signed sample, e.g.:

```sh
# create a tiny unsigned PDF, then sign it with openssl pkcs7 detached, or reuse any
# sample produced by your own openssl test pipeline, and place it at the path above.
```

The file is retained on the developer's working tree (`git check-ignore` will list it);
only its tracked copy was removed. No application source changes are needed.

## `crates/sign/tests/data/x509-rsa-sha1.pdf`

Same rationale: a PDF with an `adbe.x509.rsa_sha1` signature (raw DER in the hex blob).
Regenerate with openssl if the signature-verification tests are run locally.

## `crates/sign/tests/data/*.p12`

Seven synthetic PKCS#12 keystores (`rsa-aes.p12`, `rsa-legacy.p12`, `ec-p256.p12`,
`ec-legacy.p12`, `ec-p384.p12`, `chain.p12`, `chain-legacy.p12`) exercised by the
`crates/sign` integration tests. They contain throwaway self-signed test keys only —
the password of every keystore is `test` — but private-key material, even synthetic,
is never committed to a public repository, and neither are binaries.

Regenerate equivalents with OpenSSL 3 (any fresh keys work; the tests check the
keystore formats, not particular key values):

```sh
# RSA 2048 keystore, modern (PBES2 AES-256) and legacy (RC2/3DES, SHA-1 MAC) exports:
openssl req -x509 -newkey rsa:2048 -nodes -keyout rsa.key -out rsa.crt -days 3650 \
  -subj "/CN=Test Signer RSA"
openssl pkcs12 -export -inkey rsa.key -in rsa.crt -out rsa-aes.p12 -passout pass:test
openssl pkcs12 -export -legacy -inkey rsa.key -in rsa.crt -out rsa-legacy.p12 -passout pass:test

# EC P-256 / P-384 keystores (modern plus legacy re-export):
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ec.key \
  -out ec.crt -days 3650 -subj "/CN=Test Signer EC"
openssl pkcs12 -export -inkey ec.key -in ec.crt -out ec-p256.p12 -passout pass:test
openssl pkcs12 -export -legacy -inkey ec.key -in ec.crt -out ec-legacy.p12 -passout pass:test
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes -keyout ec3.key \
  -out ec3.crt -days 3650 -subj "/CN=Test Signer P384"
openssl pkcs12 -export -inkey ec3.key -in ec3.crt -out ec-p384.p12 -passout pass:test

# Chain keystore: leaf certificate signed by a small test root, CA cert included:
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key \
  -out ca.crt -days 3650 -subj "/CN=Test Root CA" -addext "basicConstraints=critical,CA:TRUE"
openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=Test Leaf"
openssl x509 -req -in leaf.csr -CA ca.crt -CAkey ca.key -set_serial 1 -days 3650 \
  -out leaf.crt
openssl pkcs12 -export -inkey leaf.key -in leaf.crt -certfile ca.crt \
  -out chain.p12 -passout pass:test
openssl pkcs12 -export -legacy -inkey leaf.key -in leaf.crt -certfile ca.crt \
  -out chain-legacy.p12 -passout pass:test
```

Place the generated files in `crates/sign/tests/data/`. `crates/sign/tests/data/README.md`
documents the exact certificate subjects and algorithm variants each fixture uses if you
want byte-format-identical replacements rather than equivalent ones.

## `crates/ui-egui/tests/data/form.pdf`

A one-page sample PDF with AcroForm text fields, used by the UI test suites as a
fixture for field listing, filling and signing flows. It is a binary and stays
untracked for the same hygiene reason. If it is missing, either reuse it from an
existing development working tree (the tests reference it via `include_bytes!`, so
the file must simply exist at this path before `cargo test` runs), or rebuild any
one-page PDF that declares an `/AcroForm` dictionary with a handful of text fields —
many PDF sample generators and the upstream project's published test data provide one.
