J # ==============================================================================
# ARQUIVO: Gerente_Geral_Paulistao_v31.ps1
# PROJETO: PAULISTÃO MASTER - VERSÃO "SEM RETRABALHO" E LIMPEZA
# ==============================================================================
# CORREÇÕES V31:
# 1. PULA JÁ ATUALIZADOS: Compara data do arquivo final com o original.
# 2. LIMPEZA: Ignora mensagens com mais de 2000 caracteres (docs colados).
# 3. VISUAL: Mostra claramente o que está sendo pulado.
# ==============================================================================

# --- 1. INÍCIO ---
if ($PSScriptRoot) { Set-Location -Path $PSScriptRoot } else { Set-Location -Path $PWD }
$cronometro = [System.Diagnostics.Stopwatch]::StartNew()

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   GERENTE GERAL V31 (OTIMIZADO)                          " -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan

# Define datas prioritárias
$hojeStr = (Get-Date).ToString("yyyyMMdd")       
$ontemStr = (Get-Date).AddDays(-1).ToString("yyyyMMdd") 

Write-Host "Prioridade: $hojeStr e $ontemStr" -ForegroundColor Magenta
Write-Host "Modo: Pular pastas atualizadas? SIM" -ForegroundColor Red
Write-Host "Pressione ENTER para começar..."
Read-Host

# --- CAMINHOS ---
$pastaDownloads = "C:\Users\Marcelo\Downloads\01_Inbox_WhatsApp"
$pastaDestino = Join-Path (Get-Location) "ConversasOrganizadas"
$nomeScriptPython = Join-Path (Get-Location) "motor_v31.py"

# --- 2. EXTRAÇÃO ---
Write-Host "`n[FASE 1] VERIFICANDO ZIPS..." -ForegroundColor Yellow
if (!(Test-Path $pastaDestino)) { New-Item -ItemType Directory -Path $pastaDestino | Out-Null }

if (Test-Path $pastaDownloads) {
    # Ordenação por prioridade
    $zips = Get-ChildItem -Path $pastaDownloads -Filter "conversa*.zip" | 
        Sort-Object @{Expression={
            if($_.Name -match $hojeStr){0}
            elseif($_.Name -match $ontemStr){1}
            else{2}
        }}, LastWriteTime -Descending
} else {
    Write-Host "ERRO: Pasta de origem não existe!" -ForegroundColor Red
    Exit
}

if ($zips) {
    foreach ($zip in $zips) {
        $nomeSemCopia = $zip.BaseName -replace "\s\(\d+\)$", ""
        if ($nomeSemCopia -match " com (.*)") { $nomeLimpo = $matches[1].Trim() } else { $nomeLimpo = $nomeSemCopia }
        
        $pastaConversa = Join-Path $pastaDestino $nomeLimpo
        $pastaAudios = Join-Path $pastaConversa "Audios"
        
        # CHECAGEM INTELIGENTE DE DATA
        $caminhoTxt = Join-Path $pastaConversa "Chat_Texto.txt"
        
        # Se já existe o texto, verifica se o zip é mais novo que o texto extraído
        if (Test-Path $caminhoTxt) {
            $dataTxt = (Get-Item $caminhoTxt).LastWriteTime
            $dataZip = $zip.LastWriteTime
            
            # Se o zip não é mais novo que o texto, não precisa reextrair
            if ($dataZip -le $dataTxt) {
                # Write-Host "   [ZIP JÁ EXTRAÍDO] $nomeLimpo" -ForegroundColor DarkGray
                continue
            }
        }

        if ($zip.Name -match $hojeStr -or $zip.Name -match $ontemStr) {
            Write-Host "   [ATUALIZANDO PRIORIDADE] $nomeLimpo" -ForegroundColor Magenta
        } else {
            Write-Host "   [ATUALIZANDO] $nomeLimpo" -ForegroundColor Green
        }
        
        $temp = Join-Path $pastaDestino "temp_extract"
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            Expand-Archive -Path $zip.FullName -DestinationPath $temp -Force
            if (!(Test-Path $pastaConversa)) { New-Item -ItemType Directory -Path $pastaConversa -Force | Out-Null }
            if (!(Test-Path $pastaAudios)) { New-Item -ItemType Directory -Path $pastaAudios -Force | Out-Null }

            $txt = Get-ChildItem $temp -Filter "*.txt" -Recurse | Select-Object -First 1
            if ($txt) { Move-Item $txt.FullName (Join-Path $pastaConversa "Chat_Texto.txt") -Force }
            
            $midias = Get-ChildItem $temp -Include "*.opus", "*.ogg", "*.mp3", "*.m4a", "*.wav", "*.jpg", "*.jpeg", "*.png", "*.mp4" -Recurse
            foreach ($m in $midias) {
                $novoNome = "{0}_{1}{2}" -f $m.BaseName, $nomeLimpo, $m.Extension
                $dest = Join-Path $pastaAudios $novoNome
                if (!(Test-Path $dest)) { Move-Item $m.FullName $dest -Force }
            }
        } catch {}
        finally { if (Test-Path $temp) { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue } }
    }
}

# --- 3. MOTOR PYTHON OTIMIZADO ---
Write-Host "`n[FASE 2] PROCESSAMENTO INTELIGENTE (PULA JÁ ATUALIZADOS)..." -ForegroundColor Yellow

$caminhoPythonEscapado = $pastaDestino -replace "\\", "\\"

$codigoPython = @"
import os
import sys
import re
import json
import warnings
from pathlib import Path
from datetime import datetime

try:
    from tqdm import tqdm
    import whisper
except:
    pass

warnings.filterwarnings('ignore')
PASTA_RAIZ = Path(r'$caminhoPythonEscapado')
MODELO = 'base' 

def carregar_memoria(pasta):
    arq = pasta / 'memoria_transcricoes.json'
    if arq.exists():
        try: return json.load(open(arq, encoding='utf-8'))
        except: return {}
    return {}

def salvar_memoria(pasta, dados):
    json.dump(dados, open(pasta / 'memoria_transcricoes.json', 'w', encoding='utf-8'), indent=4, ensure_ascii=False)

def ler_arquivo_seguro(caminho):
    for enc in ['utf-8', 'latin-1', 'cp1252']:
        try: return open(caminho, 'r', encoding=enc).readlines()
        except: continue
    return []

def main():
    if not PASTA_RAIZ.exists(): return

    # Ordena por modificacao
    pastas = sorted([p for p in PASTA_RAIZ.iterdir() if p.is_dir()], key=lambda x: x.stat().st_mtime, reverse=True)
    
    print(f'[PY] Analisando {len(pastas)} pastas...')
    
    # Carrega modelo SOMENTE se necessario
    model = None

    with tqdm(total=len(pastas), unit='chat') as pbar:
        for pasta in pastas:
            chat_txt = pasta / 'Chat_Texto.txt'
            final_txt = pasta / 'Chat_Completo_Leitura.txt'
            audios_dir = pasta / 'Audios'
            
            pbar.set_description(f'{pasta.name[:20]}')

            if not chat_txt.exists():
                pbar.update(1)
                continue

            # --- A MÁGICA: CHECAGEM DE DATA ---
            # Se o arquivo final existe E é mais novo que o texto original, PULA TUDO.
            if final_txt.exists():
                time_original = chat_txt.stat().st_mtime
                time_final = final_txt.stat().st_mtime
                # Se o arquivo final foi modificado DEPOIS do texto original, nao precisa refazer
                if time_final > time_original:
                    # Ja esta atualizado, pula instantaneamente
                    pbar.update(1)
                    continue
            
            # --- SE CHEGOU AQUI, PRECISA TRABALHAR ---
            if model is None:
                # Carrega o modelo so agora (economiza tempo de load se tudo estiver pronto)
                try: model = whisper.load_model(MODELO)
                except: break

            memoria = carregar_memoria(pasta)
            linhas = ler_arquivo_seguro(chat_txt)
            houve_mudanca = False
            audios_para_deletar = []

            with open(final_txt, 'w', encoding='utf-8') as f_out:
                f_out.write(f'=== HISTORICO: {pasta.name} ===\n\n')
                
                for line in linhas:
                    # --- FILTRO DE LIMPEZA: PULA TEXTOS GIGANTES ---
                    if len(line) > 2000: 
                        f_out.write('[...TEXTO LONGO OMITIDO...]\n')
                        continue
                    
                    f_out.write(line)
                    
                    match = re.search(r'([\w-]+\.(opus|ogg|mp3|m4a|wav))', line, re.IGNORECASE)
                    if match:
                        nome_original = match.group(1)
                        stem = Path(nome_original).stem
                        
                        if nome_original in memoria:
                            f_out.write(f'\n    🎙️ [MEMORIA]: \"{memoria[nome_original]}\"\n    ' + '-'*30 + '\n\n')
                            # Marca para limpeza se existir arquivo fisico renomeado
                            busca = list(audios_dir.glob(f'{stem}*'))
                            if busca: audios_para_deletar.append(busca[0])
                        else:
                            # Procura arquivo
                            busca = list(audios_dir.glob(f'{stem}*'))
                            if busca:
                                try:
                                    res = model.transcribe(str(busca[0]))
                                    texto = res['text'].strip()
                                    memoria[nome_original] = texto
                                    houve_mudanca = True
                                    f_out.write(f'\n    🎙️ [NOVO]: \"{texto}\"\n    ' + '-'*30 + '\n\n')
                                    audios_para_deletar.append(busca[0])
                                except: pass

            if houve_mudanca: salvar_memoria(pasta, memoria)
            
            # Limpeza dos .opus ja processados
            for audio in audios_para_deletar:
                if audio.suffix.lower() == '.opus':
                    try: os.remove(audio)
                    except: pass
            
            pbar.update(1)

    print('\n[PY] Concluído.')

if __name__ == '__main__':
    main()
"@

Set-Content -Path $nomeScriptPython -Value $codigoPython -Encoding UTF8

try {
    python $nomeScriptPython
} catch {}

# --- 4. RESULTADO ---
$cronometro.Stop()
$arquivoFinal = Join-Path $pastaDestino "00_TIMELINE_GLOBAL_OBRAS.txt"

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   FIM DA OPERAÇÃO (MODO INTELIGENTE)                     " -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Tempo: $($cronometro.Elapsed.ToString('hh\:mm\:ss'))"

# Abre o arquivo global se existir (Ainda vou criar no V32 se precisar)
# Por enquanto abre a pasta para conferencia
Invoke-Item $pastaDestino

Write-Host "`nPressione ENTER para fechar."
Read-Host