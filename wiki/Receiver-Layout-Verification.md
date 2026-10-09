# libautoreceiver.so layout verification, MHI2_ER_VWG13_P4521 (MU1367)

Files, copied from the head unit (not distributed here): `libautoreceiver.so`
(sha256 `b04cb5cf...`), `gal` (sha256 `f8472217...`).
Tool: `tools/armre.py` (needs the Python `capstone` package).

| Assumption in aa_hook | Evidence in this build | Result |
|---|---|---|
| Endpoint +4 open flag, +5 channel | ProtocolEndpointBase::onChannelOpened stores r1 at +5, 1 at +4 | match |
| Endpoint +8 router, +12 service id | ackFrames/setVideoFocus load [+8] as router; MessageRouter::registerService reads byte +0xc | match |
| Router endpoint table (id+64)*4 | MessageRouter::registerService, handleChannelOpenReq, routeMessage | match |
| VideoSink vtable slots 0-2, 7-14 | _ZTV9VideoSink relocations: D1, D0, onChannelClosed, ..., addDiscoveryInfo(7), handleSetup(8), handleCodecConfig(9), handleDataAvailable(10), playbackStart(11), playbackStop(12), handleMediaConfiguration(13), handleVideoFocusRequest(14), getNumberOfConfigurations(15) | match |
| Endpoint base vtable slots 5 (route), 7 (discovery, pure virtual) | _ZTV20ProtocolEndpointBase relocations | match |
| Sink +0x18 session | MediaSinkBase::handleStart stores Start+0x28 at +0x18 | match |
| Sink +0x14 codec type, +0x4c | VideoSink::addDiscoveryInfo copies +0x14 to media+0x28 and +0x4c to config+0x40 | match |
| Sink +0x1c max unacked | MediaSinkBase::sendConfig reads +0x1c | match |
| Sink +0x30 auto-focus flag | VideoSink::handleSetup tests byte +0x30 before setVideoFocus(1,1) | match |
| Sink +0x40/+0x44 config vector, 8-byte elements | getNumberOfConfigurations, addSupportedConfiguration | match |
| handleSetup: codec 3 only, sendConfig(2) | VideoSink::handleSetup | match |
| VideoConfiguration size 0x48, +0x28 resolution, string +0x08/+0x18/+0x1c | addSupportedConfiguration new(0x48), stores at +0x28..+0x44; Clear() clears string at +4 | match |
| Response +0x28/+0x2c services; service +0x58 id, +0x2c media, +0x20 bits, +0x30 input | VideoSink/InputSource::addDiscoveryInfo | match |
| Media +0x40/+0x44 configurations | VideoSink::addDiscoveryInfo | match |
| shared_ptr<IoBuffer> +4; IoBuffer base +0, offset +8, end +12 | VideoSink::handleDataAvailable, MessageRouter::routeMessage | match |
| ChannelOpenRequest +0x2c, VideoFocusRequest +0x2c | handleChannelOpenReq, handleVideoFocusRequest | match |
| Controller +4 open, +5 channel, +8 router; response u16 BE major/minor | sendVersionRequest, handleVersionResponse | match |

Open point: the stock sendVersionRequest here asks for protocol 1.2. The hook asks for 4.3 and
rewrites the phone's answer to 1.7 for gal. Whether this gal accepts 1.7 is untested; watch
`version.response` in the hook log on the first car run.
