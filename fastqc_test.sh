#!/bin/bash

# Quality control report
# Link: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/

# Argumentos dentro da função:
# $1 caminho de entrada dos dados INPUT_DIR
# $2 caminho de saída dos resultados OUTPUT_DIR
INPUT_DIR=$1
OUTPUT_DIR=$2

# Parâmetros padrões ou personalizados pelo usuário
	source "${HOME}/repos/ngs-scripts/param/fastqc.param"

# Análise propriamente dita
for base_name in $(find ${INPUT_DIR}/. -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort); do
	FASTQC_DIR="${OUTPUT_DIR}/${base_name}/fastqc"
	echo "Criando a pasta de saída nos dados ${base_name}..."
	mkdir -vp ${FASTQC_DIR}
	echo -e "Executando o fastqc nos dados disponíveis em ${base_name}...\n"
	fastqc --noextract --nogroup -o ${FASTQC_DIR} ${INPUT_DIR}/${base_name}/*
	#if [[ -n "$base_name" && ! -d "$FASTQC_DIR" ]]; then
	
	#else
	#	echo "Dados analisados previamente..."
	#fi
done	
