$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot '../Assets/Companion/Runtime'
Add-Type -Path (Join-Path $runtime 'BridgeCommand.cs'), (Join-Path $runtime 'BridgeSession.cs'), (Join-Path $PSScriptRoot 'BridgeCoreProbe.cs')
function Envelope([string]$type, [hashtable]$payload, [long]$sequence, [string]$id = [guid]::NewGuid().ToString('D')) {
    @{schemaVersion=1; messageId=$id; type=$type; sequence=$sequence; payload=$payload} | ConvertTo-Json -Depth 5 -Compress
}
function Check([bool]$value, [string]$label) { if (!$value) { throw "FAILED: $label" }; Write-Output "PASS: $label" }
$avatar = New-Object CoreTestAvatar
$session = New-Object Companion.Presentation.BridgeSession($avatar)
$init = Envelope 'avatar.initialize' @{characterId='robert'; capabilities=@('avatar.play','avatar.set_cosmetics','app.pause','app.resume')} 0
Check ($session.Receive((Envelope 'app.pause' @{} 0)).Reason -eq 'not_initialized') 'Reject pre-initialization mutation'
Check ($session.Receive($init).Accepted) 'Accept initialization'
Check ($session.Receive($init).Accepted -and $avatar.Calls -eq 1) 'Exact init retry does not mutate'
$id = [guid]::NewGuid().ToString('D')
$wave = Envelope 'avatar.play' @{animation='Wave'} 1 $id
Check ($session.Receive($wave).Accepted) 'Accept supported animation'
Check ($session.Receive((Envelope 'avatar.play' @{animation='Nod'} 2 $id)).Reason -eq 'message_id_conflict') 'Reject conflicting message ID'
Check ($session.Receive((Envelope 'app.pause' @{} 0)).Reason -eq 'stale_sequence') 'Reject stale sequence'
Check (!$session.Receive((Envelope 'avatar.play' @{animation='Wave'; text='private'} 2)).Accepted -and $avatar.Calls -eq 2) 'Reject raw text without mutation'
Check ($session.Receive((Envelope 'app.pause' @{} 2)).Accepted) 'Rejected input does not consume sequence'
$duplicate = $wave.Replace('"animation":"Wave"', '"animation":"Wave","animation":"Nod"')
Check (!$session.Receive($duplicate).Accepted) 'Reject duplicate JSON keys'
foreach ($invalid in @('{}', '', ($init + '{}'), (' ' * 4097), $init.Replace('"sequence":0','"sequence":0.5'), $init.Replace('"sequence":0','"sequence":-1'))) {
    Check (!$session.Receive($invalid).Accepted) 'Reject malformed envelope'
}
for ($i=3; $i -lt 135; $i++) { $null = $session.Receive((Envelope 'app.resume' @{} $i)) }
$before = $avatar.Calls
Check ($session.Receive($wave).Reason -eq 'stale_sequence' -and $avatar.Calls -eq $before) 'Evicted replay remains stale'
$limited = New-Object CoreTestAvatar
$limited.Installed = @('app.pause')
$limitedSession = New-Object Companion.Presentation.BridgeSession($limited)
$null = $limitedSession.Receive($init)
Check ($limitedSession.Receive((Envelope 'avatar.play' @{animation='Wave'} 1)).Reason -eq 'unsupported_capability' -and $limited.Calls -eq 1) 'Missing installed capability cannot mutate'
$limited.Available = $false
Check ($limitedSession.Receive((Envelope 'app.pause' @{} 1)).Reason -eq 'asset_unavailable' -and $limited.Calls -eq 1) 'Unavailable asset cannot mutate'
$equipment = $session.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='default'} 135))
Check ($equipment.Accepted -and $equipment.NeedsAcknowledgement) 'Equipment accepted with acknowledgement'
Check (!$session.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='unowned'} 136)).Accepted) 'Unowned equipment rejected'
# The catalogue runs on its own session: accepting a look advances the
# watermark, and the checks below depend on where the shared one is.
$wardrobeAvatar = New-Object CoreTestAvatar
$wardrobe = New-Object Companion.Presentation.BridgeSession($wardrobeAvatar)
$null = $wardrobe.Receive($init)
$earned = $wardrobe.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='sunset'} 1))
Check ($earned.Accepted -and $earned.NeedsAcknowledgement) 'An earned catalogue look is accepted'
Check (!$wardrobe.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='SUNSET'} 2)).Accepted) 'Catalogue ids are matched exactly'
$outfit = $wardrobe.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='arab-thobe'} 3))
Check ($outfit.Accepted -and $outfit.NeedsAcknowledgement) 'A modelled outfit is a catalogue look'
Check (!$wardrobe.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='arab_thobe'} 4)).Accepted) 'An asset folder name is not a cosmetic id'
$avatar.AcceptCommands = $false
$before = $avatar.Calls
Check ($session.Receive((Envelope 'avatar.play' @{animation='Wave'} 136)).Reason -eq 'presentation_rejected' -and $avatar.Calls -eq $before) 'Paused/rejected presentation does not falsely signal asset failure'
$avatar.AcceptCommands = $true
Check ($session.Receive((Envelope 'app.resume' @{} 136)).Accepted) 'Presentation rejection preserves sequence for resume'
$before = $avatar.Calls
Check ($session.Receive((Envelope 'app.pause' @{} 9007199254740992)).Reason -eq 'invalid_envelope' -and $avatar.Calls -eq $before) 'Reject first integer above JSON-safe limit without mutation'
Check ($session.Receive((Envelope 'app.pause' @{} ([long]::MaxValue))).Reason -eq 'invalid_envelope' -and $avatar.Calls -eq $before) 'Reject signed-long maximum without mutation'
Check ($session.Receive((Envelope 'app.pause' @{} 9007199254740991)).Accepted -and $avatar.Calls -eq ($before + 1)) 'Accept JSON-safe maximum after rejected overflow'
# Capability negotiation, faces and reinitialization on a fresh session.
$extra = New-Object CoreTestAvatar
$narrow = New-Object Companion.Presentation.BridgeSession($extra)
$narrowInit = Envelope 'avatar.initialize' @{characterId='robert'; capabilities=@('avatar.play','avatar.set_emotion','app.pause')} 0
Check ($narrow.Receive($narrowInit).Accepted) 'Accept initialization with a narrower capability set'
Check (($narrow.Capabilities -join ',') -eq 'avatar.play,avatar.set_emotion,app.pause') 'Report only negotiated capabilities'
Check ($narrow.Receive((Envelope 'avatar.set_emotion' @{emotion='happy'} 1)).Accepted) 'Accept allowlisted emotion'
Check (!$narrow.Receive((Envelope 'avatar.set_emotion' @{emotion='angry'} 2)).Accepted) 'Reject unlisted emotion'
Check ($narrow.Receive((Envelope 'avatar.set_cosmetics' @{cosmeticId='default'} 2)).Reason -eq 'unsupported_capability') 'A capability left out of negotiation cannot be used'
Check ($narrow.Receive((Envelope 'avatar.initialize' @{characterId='robert'; capabilities=@('app.pause')} 2)).Reason -eq 'already_initialized') 'Reject a second, different initialization'
Check (!$narrow.Receive((Envelope 'avatar.play' @{animation='Dance'} 2)).Accepted) 'Reject an unlisted animation'
Check (!$narrow.Receive((Envelope 'avatar.initialize' @{characterId='someone-else'; capabilities=@()} 2)).Accepted) 'Reject a foreign character'
Check ($narrow.Receive((Envelope 'app.pause' @{} 2)).Accepted) 'Rejections left the sequence available'

Write-Output 'Bridge core checks passed. This is the engine-free core only; run Test-EditMode.ps1 for the receiver, and neither covers rendering, the Android export or a device.'
