# iPhone imagery acceptance preview

This isolated branch reconciles imagery candidate 1f6138d and reopen repair 825eb8c with released main 41d1aaf. It includes no unified station implementation. The workflow publishes only the explicit Cloudflare preview branch `imagery-iphone-acceptance`; production remains held.

Use a physical iPhone in Safari: pan/pinch the yard map, include satellite imagery, cancel during transfer, retry, confirm 1.89 total / 0.07 excluded / 1.82 net acres, then return home and reopen the saved preview graph. Check zoom responsiveness, bottom controls with Safari chrome, and the image and exclusions after reopening. The sample uses an in-memory repository: reopening works within this running tab, but reloading/closing it does not promise durable recovery. No customer files are written.

Headless mobile viewport evidence is separate from hardware acceptance. Actual provider timeouts should leave the trace intact and offer retry. Physical acceptance and production authorization remain required before release.
