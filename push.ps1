# push.ps1 — envia os commits locais para o GitHub.
#
# Os commits desta rodada de fechamento (arquivar checklist, pente fino nas
# ações, calendário/relatórios, polimento, logo HU Brasil e offline) já estão
# feitos, um por bloco. Este script só empurra o que existe.
#
# Uso:  .\push.ps1
#       .\push.ps1 "mensagem"   -> commita alterações soltas antes de enviar

param([string]$Mensagem = "")

$ErrorActionPreference = "Stop"

# Alterações não commitadas? Só entram se você passar uma mensagem.
$pendente = git status --porcelain
if ($pendente) {
    if ($Mensagem -eq "") {
        Write-Host "Há alterações não commitadas:" -ForegroundColor Yellow
        git status --short
        Write-Host ""
        Write-Host 'Rode: .\push.ps1 "sua mensagem de commit"' -ForegroundColor Yellow
        exit 1
    }
    git add -A
    git commit -m $Mensagem
    if (-not $?) { exit 1 }
}

$branch = git rev-parse --abbrev-ref HEAD
Write-Host "Enviando '$branch' para o origin..." -ForegroundColor Cyan
git push origin $branch
if ($?) { Write-Host "Push concluido." -ForegroundColor Green }
