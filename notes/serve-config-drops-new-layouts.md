# POST /config drops a new scene's layouts

Decision: monitor setups. Recorded 2026-11-17 16:52 CST.

`Save-PostedConfig` (serve.ps1:95) puts the server's layouts back on each scene (serve.ps1:106-109). A new scene has none on the server, so the layouts its body carries are dropped.

A future duplicate or import must post the scene with POST /config first, then save each layout with POST /layout. POST /layout returns 404 for a scene that is not yet saved.
