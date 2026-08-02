# Harness de conferência do vídeo. Calcula a linha do tempo real (mesma regra do
# sceneDuration), mapeia cada toque pro frame global, extrai os quadros EXATOS e
# monta folhas de contato. Bar do Alf: 9,5 — conferir TUDO, não amostrar.
#
# ⚠️ A extração usa `select=eq(n,FRAME)` numa passada única, e NÃO `-ss`:
# a busca por tempo (mesmo em 2 passos) entrega quadros ~8 frames adiantados
# num H.264 com B-frames, o que fez a mão parecer fora do alvo em toques que
# na verdade estavam certos. O filtergraph vai num arquivo pra não depender
# de escape de vírgula no shell.
param([string]$Video = "out/onboarding-professor.mp4", [string]$Saida = "$env:TEMP\claude\conf")

$dur = @{abertura=5.62;intro=14.58;login=6.03;home=10.48;agenda=10.11;gravar=11.91;ouvir=7.89;
  processando=9.8;confirmar=16.72;sucesso=9.17;presenca=6.9;chamada=13.56;alunos=8.83;ficha=12.12;
  turma=10.16;chat=10.79;whatsapp=9.17;semana=11.18;perfil=10.81;fecho=4.18}
$min = [ordered]@{abertura=4;intro=15;login=7;home=8;agenda=8;gravar=13;ouvir=9;processando=10;
  confirmar=18;sucesso=7;presenca=7;chamada=15;alunos=10;ficha=13;turma=7;chat=13;whatsapp=10;
  semana=8;perfil=13;fecho=5}
# frames de clique DENTRO de cada cena (espelham os keyframes do Onboarding.tsx)
$cliques = @{
  intro=@(108,318,428); login=@(22,118,164); agenda=@(28,160); gravar=@(32,300);
  ouvir=@(20,212); confirmar=@(86,206,466); chamada=@(76,180,290); alunos=@(22,190);
  chat=@(24,68,150); semana=@(24); perfil=@(20,54,120,286)
}
$OLHAR = 8   # frames após o clique: meio da permanência, com o anel visível

# CALIBRAÇÃO: o Remotion mede os MP3 (getAudioDurationInSeconds) um tico
# diferente do ffprobe, então minha linha do tempo desvia alguns frames ao
# longo do vídeo. Comparo meu total com a duração REAL do arquivo e distribuo
# a diferença proporcionalmente. Sem isso os quadros de conferência saem
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
"linha do tempo calculada: $inicio frames · real: $framesReais · fator $([math]::Round($fator,5))"
"toques a conferir: $($lista.Count)"

New-Item -ItemType Directory -Force $Saida | Out-Null
Get-ChildItem "$Saida\*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

# Extração EXATA: `-ss` DEPOIS do `-i` = seek por decodificação (o ffmpeg
# decodifica desde o início e descarta até o ponto). É lento, mas é o único
# modo que entrega o quadro pedido. Seek rápido (-ss antes do -i, mesmo em
# 2 passos) cai no keyframe e devolve quadros ~8 frames adiantados — foi o que
# fez toques certos parecerem errados na 1ª rodada de conferência.
# (A passada única com select=eq(n,X) seria mais rápida, mas o muxer de
# sequência image2 %03d falha neste build do ffmpeg do Remotion.)
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
