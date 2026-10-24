# NOTE: the clips now in audio/voices come from Cartesia (see scripts/voice.gd); running this script would overwrite them with the Windows voices.
# Renders the game's few voiced lines to WAV with the Windows voices installed on this machine (no API, no runtime dependency):
#   powershell -ExecutionPolicy Bypass -File tools/make_voices.ps1
# Reads tools/voice_lines.json, writes audio/voices/<sha1 of the subtitle text, 12 hex>.wav, num_N.wav (the Commander's kill count),
# cmd_rest.wav / cmd_many.wav and audio/voices/index.json (hash -> style). Voice.gd finds a clip by hashing the subtitle it is shown.
# Pitch / rate per speaker are baked in here (SSML prosody); Voice.gd only varies the playback pitch a little per soldier.
Add-Type -AssemblyName System.Speech
$proj = Split-Path -Parent $PSScriptRoot
$out = Join-Path $proj "audio\voices"
New-Item -ItemType Directory -Force $out | Out-Null
$cfg = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "voice_lines.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$sha = [System.Security.Cryptography.SHA1]::Create()

function Render($style, $say, $file) {
    $st = $cfg.styles.$style
    $synth.SelectVoice($st.voice)
    $esc = [Security.SecurityElement]::Escape($say)
    $ssml = "<speak version=`"1.0`" xmlns=`"http://www.w3.org/2001/10/synthesis`" xml:lang=`"$($st.lang)`"><prosody pitch=`"$($st.pitch)`" rate=`"$($st.rate)`">$esc</prosody></speak>"
    $synth.SetOutputToWaveFile($file, $fmt)
    $synth.SpeakSsml($ssml)
    $synth.SetOutputToNull()
}

function Words([int]$n) {
    $ones = "zero","one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen"
    $tens = "","","twenty","thirty","forty","fifty","sixty"
    if ($n -lt 20) { return $ones[$n] }
    $t = [math]::Floor($n / 10); $o = $n % 10
    if ($o -eq 0) { return $tens[$t] }
    return $tens[$t] + "-" + $ones[$o]
}

$index = @{}
foreach ($l in $cfg.lines) {
    $h = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($l.text))) -replace "-", "").ToLower().Substring(0, 12)
    Render $l.style $l.say (Join-Path $out "$h.wav")
    $index[$h] = $l.style
    Write-Host "$h  $($l.style)  $($l.text)"
}
for ($n = 1; $n -le $cfg.commander_count_max; $n++) {
    $w = Words $n
    Render "commander" ($w.Substring(0, 1).ToUpper() + $w.Substring(1) + " ...") (Join-Path $out "num_$n.wav")
}
Render "commander" $cfg.commander_count_rest (Join-Path $out "cmd_rest.wav")
Render "commander" $cfg.commander_count_many (Join-Path $out "cmd_many.wav")
$index["_count_max"] = $cfg.commander_count_max
[IO.File]::WriteAllText((Join-Path $out "index.json"), ($index | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
Write-Host "done: $((Get-ChildItem $out -Filter *.wav).Count) clips"
