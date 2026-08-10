# Apaga o clone nested que apareceu em D:\la-teacher\la-teacher\
# e o lixo movido pra fora, se existir.
# Rodar DEPOIS de abrir o Cursor em D:\la-teacher (não na pasta nested).

$ErrorActionPreference = 'Stop'
$nested = 'D:\la-teacher\la-teacher'
$lixo = 'D:\la-teacher-NESTED-LIXO-APAGAR'

if ((Get-Location).Path -like '*\la-teacher\la-teacher*') {
  Write-Error 'Feche este workspace e abra D:\la-teacher antes de rodar este script.'
}

foreach ($p in @($nested, $lixo)) {
  if (Test-Path -LiteralPath $p) {
    Write-Host "Apagando $p ..."
    Remove-Item -LiteralPath $p -Recurse -Force
    Write-Host "OK: $p removido."
  } else {
    Write-Host "Nada em $p"
  }
}

git -C D:\la-teacher status -sb
