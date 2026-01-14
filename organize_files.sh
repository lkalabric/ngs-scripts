#!/bin/bash

# ==============================================================================
# Script: organizar_arquivos.sh
# Descrição: Lê arquivos de um diretório, identifica a raiz do nome e os organiza
#            em pastas baseadas nessa raiz.
# ==============================================================================

# Diretório alvo (padrão é o diretório atual se nenhum for passado)
TARGET_DIR="${1:-.}"

# Verifica se o diretório existe
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Erro: O diretório '$TARGET_DIR' não existe."
    exit 1
fi

echo "Iniciando a organização em: $TARGET_DIR"

# Entra no diretório para facilitar a manipulação
cd "$TARGET_DIR" || exit

# Loop por todos os arquivos no diretório
for file in *; do
    # Pula se for um diretório ou o próprio script
    if [[ -d "$file" || "$file" == "organizar_arquivos.sh" ]]; then
        continue
    fi

    # Identifica a raiz do nome. 
    # Aqui, definimos 'raiz' como tudo antes do PRIMEIRO ponto ou sublinhado.
    # Exemplo: 'amostra01_R1.fastq' -> 'amostra01'
    # Exemplo: 'relatorio.v1.pdf'    -> 'relatorio'
    
    # Usando Parameter Expansion para pegar a string antes do primeiro '.' ou '_'
    # Tentamos primeiro o sublinhado, depois o ponto.
    root_name="${file%%_*}"
    root_name="${root_name%%.*}"

    # Se por algum motivo a raiz ficar vazia, pula o arquivo
    if [[ -z "$root_name" ]]; then
        continue
    fi

    # Cria o diretório da raiz se não existir
    if [[ ! -d "$root_name" ]]; then
        echo "Criando pasta: $root_name"
        mkdir -p "$root_name"
    fi

    # Move o arquivo para a pasta correspondente
    echo "Movendo '$file' -> '$root_name/'"
    mv "$file" "$root_name/"
done

echo -e "\nOrganização concluída com sucesso!"
