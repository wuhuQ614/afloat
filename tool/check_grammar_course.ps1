$ErrorActionPreference = 'Stop'
$path = 'e:\YINGYU\YINGYU\smartenglish-desktop\assets\grammar_course.json'
$bytes = [System.IO.File]::ReadAllBytes($path)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Write-Host 'ERROR: BOM found' ; exit 1 }
$json = [System.Text.Encoding]::UTF8.GetString($bytes)
$data = $json | ConvertFrom-Json

$errors = @()
$topics = @()
foreach ($lv in $data.levels) { foreach ($t in $lv.topics) { $topics += $t } }

$expected = @('L0-01','L0-02','L1-01','L1-02','L1-03','L1-04','L2-01','L2-02','L3-01','L3-02','L3-03','L3-04','L3-05','L4-01','L5-01','L5-02','L5-03','L5-04','L5-05')
if ($topics.Count -ne 19) { $errors += "topic count $($topics.Count) != 19" }
$ids = $topics | ForEach-Object { $_.id }
foreach ($e in $expected) { if ($ids -notcontains $e) { $errors += "missing topic $e" } }

$refs = New-Object System.Collections.Generic.HashSet[int]
foreach ($t in $topics) {
    $sr = $t.syllabusRef
    if ($sr -is [array]) { foreach ($r in $sr) { [void]$refs.Add([int]$r) } } else { [void]$refs.Add([int]$sr) }
}
for ($i = 1; $i -le 22; $i++) { if (-not $refs.Contains($i)) { $errors += "syllabusRef $i not covered" } }

$total = 0
$dist = @{A=0;B=0;C=0;D=0}
foreach ($t in $topics) {
    $ilen = $t.intro.Length
    if ($ilen -lt 300 -or $ilen -gt 600) { $errors += "$($t.id) intro length $ilen out of 300-600" }
    $qc = $t.quiz.Count
    if ($qc -lt 6 -or $qc -gt 8) { $errors += "$($t.id) quiz count $qc out of 6-8" }
    $total += $qc
    $ec = $t.examples.Count
    if ($ec -lt 3 -or $ec -gt 6) { $errors += "$($t.id) examples count $ec out of 3-6" }
    for ($k = 0; $k -lt $qc; $k++) {
        $q = $t.quiz[$k]
        if ($q.options.Count -ne 4) { $errors += "$($t.id) q$k options != 4" }
        if ($q.answer -notin @('A','B','C','D')) { $errors += "$($t.id) q$k bad answer" }
        else { $dist[$q.answer]++ }
    }
}

Write-Host "levels: $($data.levels.Count) | topics: $($topics.Count) | questions: $total"
Write-Host "answer distribution: A=$($dist.A) B=$($dist.B) C=$($dist.C) D=$($dist.D)"
Write-Host "syllabus coverage: $((1..22 | Where-Object { $refs.Contains($_) }) -join ',')"
if ($errors.Count -gt 0) { Write-Host 'ERRORS:'; $errors | ForEach-Object { Write-Host " - $_" }; exit 1 }
Write-Host 'ALL CHECKS PASSED'
