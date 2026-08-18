# Initial Web Deployment Report (R7)

## Deployment target

- Project: `SD_STORY_RPG_GODOT`
- Revision: `R7` (fixed output names; no new revision number created)
- Engine: Godot 4.7.1 Stable Standard
- Renderer: Compatibility
- Target: Web/HTML offline runtime
- Audio: out of scope; existing hooks remain intact
- Public hosting: not configured in this project; no external upload was performed

## Delivered artifacts

- Release directory: `builds/web_r7_current_release/`
- Initial deployment ZIP: `builds/SD_STORY_RPG_R7_INITIAL_WEB.zip`
- ZIP size: `272,053,440` bytes
- ZIP SHA-256: `0E1824A626A38D797426365F2DE26D3E302E8F61E079D96728710293EF51407E`
- Build ID: `LANTERNLINE_R7_CURRENT_WEB`
- Runtime PCK: `r7_current_72afe8d01baf.pck`
- Runtime WASM: `r7_current_72afe8d01baf.wasm`

## Local deployment

- URL: `http://127.0.0.1:8081/index.html?build=r7_current`
- Server: Python 3.11 `http.server`, bound to loopback only
- Server is running in the background for local review; no internet exposure

## In-app browser verification

- HTTP page loaded successfully in the in-app browser.
- Title screen rendered.
- Home screen rendered after the start action.
- Chapter 1 hex traversal map rendered from the home screen.
- Browser console error/warning check: 0 captured during this smoke check.
- The temporary in-app browser QA tab was closed after verification; the fixed local deployment URL remains available while the local server is running.

## Scope boundaries

- This is an offline local Web deployment, not a public cloud deployment.
- Windows EXE, APK, and AAB were not created.
- No external paid API, runtime download, or cloud service was used.
