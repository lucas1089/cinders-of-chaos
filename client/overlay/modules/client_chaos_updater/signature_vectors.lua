-- Ed25519 and SHA-256 vectors for the client's native check (g_crypt.ed25519Verify, g_crypt.sha256Encode):
-- ChaosUpdater.selfTest() runs them in the client (client/MANIFEST.md "Signed updater", tests). The same vectors are
-- checked natively by client/tools/chaosupdate_test.cpp and the signer by client/tools/make_update_manifest_test.py.
return {
  -- RFC 8032 section 7.1, tests 1-3: public key, message (hex), signature
  rfc8032 = {
    { 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', '',
      'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b' },
    { '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c', '72',
      '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00' },
    { 'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025', 'af82',
      '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a' },
  },
  -- a payload signed by make_update_manifest.py with the RFC 8032 test 1 key
  manifest = {
    key = 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
    payload = '{"channel":"live","created":"2026-10-10T00:00:00Z","files":[{"path":"modules/game_a/a.lua","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","size":3}],"files_url":"files/","format":1,"min_package":0,"min_version":0,"parallel":4,"product":"cinders-of-chaos","version":1}',
    signature = 'd337bacbfcba1dbb7ba21f567099078f295b587f876d1cd1a82a401dfde31d465b0a7ad4ac277b6cda5026644ae061d88b8ecf882637a279c82d5c73eac88601',
  },
  sha256 = { abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' },
}
