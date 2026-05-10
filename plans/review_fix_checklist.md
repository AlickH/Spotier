# Review Fix Checklist

- [x] Fix CloudKit sync conflict resolution so different contents never stall when timestamps are too close.
- [x] Remove hidden CloudKit local-only fallback when the schema is missing; surface a real failure and turn off the misleading enabled state.
- [x] Fail tunnel startup when no TUN file descriptor can be obtained instead of reporting a false success.
- [x] Persist config selection and use it for launch auto-connect instead of always picking the first config file.
- [x] Add or update tests for the changed behavior.
- [x] Remove dead CLI peer-fetching code and other unused runner methods.
- [x] Remove hardcoded log path fallback and string-path log API.
- [x] Remove redundant VPN profile second-save logic.
- [x] Simplify VPN/config state management further where duplicated branches remain.
- [x] Re-run repository tests after the broader cleanup pass.
