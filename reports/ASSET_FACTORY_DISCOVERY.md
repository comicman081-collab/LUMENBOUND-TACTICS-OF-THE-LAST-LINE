# Asset Factory Discovery

## Search scope

- Initial workspace and parents through `Documents`
- `D:\AI 종합 폴더\Games`
- directories containing `asset_share`
- no whole-drive brute-force search

## Canonical result

- Path: `D:\AI 종합 폴더\Games\asset_share`
- Package: `asset-share-procedural-factory`
- Package version: `0.1.0`
- Factory generatorVersion found in manifests: `1.0.0`
- TypeScript 5.9.2 / Three.js 0.179.1
- Manifest files: 214; JSON parse failures: 0
- Export PNG files observed: 300
- Unit/regression test files observed: 19
- Report artifacts observed: 120

Canonical criteria:

1. All 214 manifests parse: PASS.
2. `generatorVersion`: PASS.
3. core storage/production and export layers: PASS.
4. `generated/` and `exports/` separation: PASS.
5. recent version plus deterministic/unit/smoke/QA tests: PASS.

The source factory was not modified. The bridge selected latest manifest versions in five visual categories, validated manifest/output SHA and PNG IHDR, then copied only configured PNG/atlas outputs.

## Baseline SHA-256

- `package.json`: `B98EF215A4F34BAA81E718A9CD1FAEC48B8E5740C31D3CEEE8947C11919D1967`
- `asset-path-resolver.ts`: `FEB34C6D4207734E45A9C3B279AE24F312E4AB17DA57037E102634A98B915AC7`
- sample v3 character manifest: `C3E88B317C8DB74378952D7C07A17D71933FBA115A115488953FB746A558F7DD`

