# windows-assets (private build inputs, not code)

Inputs of the `Windows package` workflow (`.github/workflows/windows-package.yml` on `main`). Nothing here is
built or edited by hand; the branch has no history in common with `main`.

| File | What it is |
|---|---|
| `server/base-server.tar.xz` | the base server download (Hellgrave_Exodus_Server_v3.7.5: engine source, Windows exe and DLLs, data, map, SQL_Server), unchanged, repacked from the uploaded `.rar` |
| `client/base-client.tar.xz.partNN` | the base client (AstraClient-main), unchanged; the parts are one file cut at 95 MB (GitHub refuses files over 100 MB): `cat base-client.tar.xz.part* > base-client.tar.xz` |
| `things/things-1098.tar.xz.partNN` | the merged Chaos `Tibia.dat` + `Tibia.spr` (10.98), the current pair (36 and later); parts of one file cut at 95 MB: `cat things-1098.tar.xz.part* > things-1098.tar.xz` |
| `things/things-1098.tar.xz` | pair 35, the last pair under 100 MB in one file; kept only while `main` still reads this name (remove it once `main` reads the parts) |
| `mapeditor/map-editor.tar.xz` | the map editor (Remere's Map Editor build for 10.98, GPL; sources: github.com/hjnilsson/rme), unchanged; the package swaps in our items.otb/items.xml and adds our monsters to its creature list |
| `backup/item-forge-cnn.tar.xz` | backup only, not a package input: the item forge model work (trained weights, training data, scripts, logs); checksum in `backup/SHA256SUMS` |
| `SHA256SUMS.parts` | checksums of the files above |

To replace one: build the new archive the same way, update `SHA256SUMS.parts`, commit to this branch.
To remove everything: delete the branch (`git push origin --delete windows-assets`).
