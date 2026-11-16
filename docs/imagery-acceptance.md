# iPhone imagery acceptance preview

This isolated branch reconciles imagery candidate 1f6138d and reopen repair 825eb8c with released main 41d1aaf. It includes no unified station implementation. The workflow publishes only the explicit Cloudflare preview branch `imagery-iphone-acceptance`; production was held pending acceptance.

Use a physical iPhone in Safari: pan/pinch the yard map, include satellite imagery, cancel during transfer, retry, confirm 1.89 total / 0.07 excluded / 1.82 net acres, then return home and reopen the saved preview graph. Check zoom responsiveness, bottom controls with Safari chrome, and the image and exclusions after reopening. The sample uses an in-memory repository: reopening works within this running tab, but reloading/closing it does not promise durable recovery. No customer files are written.

Headless mobile viewport evidence is separate from hardware acceptance. Actual provider timeouts should leave the trace intact and offer retry. Physical acceptance and production authorization were required before release.

## Production release reconciliation — 2026-11-16

Cole accepted preview `95eb46a7` on a physical iPhone and explicitly authorized release. The isolated release combines accepted preview source `546c407` (including reopen repair `825eb8c`) with deployed audit source `94604ad`. No unfinished unified station implementation is included.

The shared Fit handler preserves the audit fix for visible note bounds and layer visibility, while using compact trace framing on phones. Added desktop/mobile cases verify long notes remain visible with a trace present. Existing calibration and graph coordinates are unchanged by Fit.

The prior production rollback reference is commit `94604ad25946f3443d87f5338d416793c93e409b`, Cloudflare deployment `056703e8-7df2-4ba7-8f2b-845bbc5c6921`. Release verification evidence is recorded separately from the earlier session-only preview checks. Protected Ops Brain address lookup and customer publication require an authenticated employee session; public preview address lookup does not replace production authentication.
