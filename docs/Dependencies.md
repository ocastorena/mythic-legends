# Dependency provenance

## ProfileStore

- Runtime realm: server only
- Studio path: `ServerScriptService.Packages.ProfileStore`
- Repository path: `src/ServerScriptService/Packages/ProfileStore.luau`
- Upstream: <https://github.com/MadStudioRoblox/ProfileStore>
- Verified upstream commit: `45c9847cbcf1fc260369c50eb335aba7c35aecdd`
- Local SHA-256: `f9e2b6df89ef681318728181735ee343a145bda02b4e50c629a8c8057d559e03`
- License: `src/ServerScriptService/Packages/ProfileStore.LICENSE`

The vendored file matches the verified upstream source except for the project logging policy:
the successful DataStore-access message is removed, and the unavailable-access message is a
warning. This keeps third-party startup output consistent with the rule that normal successful
behavior does not log.

ProfileStore stays outside the generated root `Packages/` directory because that directory is
mapped to `ReplicatedStorage.Packages`. Moving a server-realm persistence library there would
replicate its source to clients. Any future dependency update must re-verify the upstream commit,
local patch, license, and checksum recorded here.

## Trove

- Runtime realm: shared
- Studio path: `ReplicatedStorage.Packages.Trove`
- Package: `sleitnick/trove@1.8.0`
- Upstream: <https://github.com/Sleitnick/RbxUtil/tree/main/modules/trove>
- License: MIT

Combat uses Trove only for lifecycle ownership: connections and cancellable tasks. Trove does
not own hit detection, server validation, combat state, presentation, or networking.
The dependency is pinned by `wally.lock` and generated into `Packages/` by `wally install`.

ShapecastHitbox is intentionally not a production dependency. Its upstream repository currently
does not publish a supported installation procedure, so the project keeps melee detection behind
its own adapter until a stable release can be evaluated and pinned.
