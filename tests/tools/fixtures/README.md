# Fixtures: a revoked key and an expired key

gpg prints a VALIDSIG status line for a signature of a revoked or an expired key, next to REVKEYSIG,
EXPKEYSIG or KEYEXPIRED. The tests use these files to check that such a signature is rejected. They hold
throwaway public keys and signatures, no private keys, and are made once so that the tests need no faketime
and no terminal (gpg --gen-revoke asks for one).

- fixture-data.txt: the signed data.
- revoked.pub, revoked.asc, revoked.fpr: a key that was revoked after signing, the signature, the fingerprint.
- expired.pub, expired.asc, expired.fpr: a key created 2020-01-01 that expired after 30 days, a signature made on
  2020-01-10, the fingerprint.

How they were made (gpg 2.4, in a container): generate an rsa2048 sign-only key, sign fixture-data.txt, create the
revocation certificate with gpg --gen-revoke (reason 0) in a terminal, import it and export the public key; the
expired key was created and used under `faketime '2020-01-01 12:00:00'` with the expiry 30d.
