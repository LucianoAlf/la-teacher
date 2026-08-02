# Harness de conferÃªncia do vÃ­deo. Calcula a linha do tempo real (mesma regra do
# sceneDuration), mapeia cada toque pro frame global, extrai os quadros EXATOS e
# monta folhas de contato. Bar do Alf: 9,5 â€” conferir TUDO, nÃ£o amostrar.
#
# âš ï¸ A extraÃ§Ã£o usa `select=eq(n,FRAME)` numa passada Ãºnica, e NÃƒO `-ss`:
# a busca por tempo (mesmo em 2 passos) entrega quadros ~8 frames adiantados
# num H.264 com B-frames, o que fez a mÃ£o parecer fora do alvo em toques que
# na verdade estavam certos. O filtergraph vai num arquivo pra nÃ£o depender
# de escape de vÃ­rgula no shell.
param([string]$Video = "out/onboarding-professor.mp4", [string]$Saida = "$env:TEMP\claude\conf")

$dur = @{abertura=5.09;agenda=8.25;alunos=8.8;chamada=13.64;chat=10.84;confirmar=14.76;fecho=3.89;ficha=12.75;gravar=12.02;home=7.97;intro=15.02;login=6.11;ouvir=7.65;perfil=11.23;presenca=5.98;processando=8.99;semana=8.44;sucesso=6.58;turma=7.55;whatsapp=8.07}
$min = [ordered]@{abertura=4;intro=15;login=7;home=8;agenda=8;gravar=13;ouvir=9;processando=10;
  confirmar=18;sucesso=7;presenca=7;chamada=15;alunos=10;ficha=13;turma=7;chat=13;whatsapp=10;
  semana=8;perfil=13;fecho=5}
# frames de clique DENTRO de cada cena (espelham os keyframes do Onboarding.tsx)
$cliques = @{
  intro=@(108,318,428); login=@(22,118,164); agenda=@(28,160); gravar=@(32,300);
  ouvir=@(20,212); confirmar=@(86,206,466); chamada=@(76,180,290); alunos=@(22,190);
  chat=@(24,68,150); semana=@(24); perfil=@(20,54,120,286)
}
$OLHAR = 8   # frames apÃ³s o clique: meio da permanÃªncia, com o anel visÃ­vel

# CALIBRAÃ‡ÃƒO: o Remotion mede os MP3 (getAudioDurationInSeconds) um tico
# diferente do ffprobe, entÃ£o minha linha do tempo desvia alguns frames ao
# longo do vÃ­deo. Comparo meu total com a duraÃ§Ã£o REAL do arquivo e distribuo
# a diferenÃ§a proporcionalmente. Sem isso os quadros de conferÃªncia saem
# deslocados e toques certos parecem errados.
$saidaFfp = & npx remotion ffmpeg -i $Video 2>&1 | Out-String
$framesReais = if ($saidaFfp -match 'Duration: (\d+):(\d+):([\d.]+)') {
  [math]::Round(([double]$Matches[1]*3600 + [double]$Matches[2]*60 + [double]$Matches[3]) * 30)
} else { 0 }

$inicio = 0; $lista = @()
foreach ($k in $min.Keys) {
  $frames = [math]::Max($min[$k] * 30, [math]::Ceiling(($dur[$k] + 0.8) * 30))
  foreach ($c in ($cliques[$k])) { $lista += [pscustomobject]@{ nome = "$k+$c"; bruto = $inicio + $c + $OLHAR } }
  $inicio += $frames
}
$fator = if ($framesReais -gt 0) { $framesReais / $inicio } else { 1 }
$lista = $lista | ForEach-Object {
  [pscustomobject]@{ nome = $_.nome; frame = [math]::Round($_.bruto * $fator) }
} | Sort-Object frame
"linha do tempo calculada: $inicio frames Â· real: $framesReais Â· fator $([math]::Round($fator,5))"
"toques a conferir: $($lista.Count)"

New-Item -ItemType Directory -Force $Saida | Out-Null
Get-ChildItem "$Saida\*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

# ExtraÃ§Ã£o EXATA: `-ss` DEPOIS do `-i` = seek por decodificaÃ§Ã£o (o ffmpeg
# decodifica desde o inÃ­cio e descarta atÃ© o ponto). Ã‰ lento, mas Ã© o Ãºnico
# modo que entrega o quadro pedido. Seek rÃ¡pido (-ss antes do -i, mesmo em
# 2 passos) cai no keyframe e devolve quadros ~8 frames adiantados â€” foi o que
# fez toques certos parecerem errados na 1Âª rodada de conferÃªncia.
# (A passada Ãºnica com select=eq(n,X) seria mais rÃ¡pida, mas o muxer de
# sequÃªncia image2 %03d falha neste build do ffmpeg do Remotion.)
$i = 0
foreach ($item in $lista) {
  $i++
  $t = ($item.frame / 30).ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
  & npx remotion ffmpeg -i $Video -ss $t -frames:v 1 -vf "scale=360:-1" "$Saida\$($item.nome).png" -y 2>$null | Out-Null
  Write-Host "  [$i/$($lista.Count)] $($item.nome)" -NoNewline:$false
}
$faltando = $lista | Where-Object { -not (Test-Path "$Saida\$($_.nome).png") }
if ($faltando) { "AVISO: faltaram $($faltando.Count) quadros: $(($faltando.nome) -join ', ')" }

# folhas de contato 3x2
Add-Type -AssemblyName System.Drawing
$arquivos = $lista | ForEach-Object { Get-Item "$Saida\$($_.nome).png" -ErrorAction SilentlyContinue }
$porFolha = 6; $cols = 3; $lw = 360; $lh = 640; $rotulo = 26
for ($i = 0; $i -lt $arquivos.Count; $i += $porFolha) {
  $lote = $arquivos[$i..([math]::Min($i + $porFolha - 1, $arquivos.Count - 1))]
  $linhas = [math]::Ceiling($lote.Count / $cols)
  $bmp = New-Object System.Drawing.Bitmap ($cols * $lw), ($linhas * ($lh + $rotulo))
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::FromArgb(12, 12, 12))
  $fonte = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
  for ($j = 0; $j -lt $lote.Count; $j++) {
    $img = [System.Drawing.Image]::FromFile($lote[$j].FullName)
    $x = ($j % $cols) * $lw; $y = [math]::Floor($j / $cols) * ($lh + $rotulo)
    $g.DrawString($lote[$j].BaseName, $fonte, [System.Drawing.Brushes]::Aquamarine, ($x + 6), ($y + 4))
    $g.DrawImage($img, $x, ($y + $rotulo), $lw, $lh)
    $img.Dispose()
  }
  $n = [math]::Floor($i / $porFolha) + 1
  $bmp.Save("$Saida\folha-$n.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  "folha-$n.png ($($lote.Count) toques)"
}
