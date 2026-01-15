#!/bin/bash

# Trimagem de apaptadores de dados de sequencias Illumina
	# Link: http://www.usadellab.org/cms/?page=trimmomatic

	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho para salvamento dos resultados OUTPUT_DIR
		INPUT_DIR=$1
		OUTPUT_DIR=$2
	echo "Input: ${INPUT_DIR}"
	echo "Output: ${OUTPUT_DIR}"

	# Parâmetros padrões ou personalizados pelo usuário
		source "${HOME}/repos/ngs-scripts/param/trimmomatic.param"

	# Habilita o trimmomatic instalado em um ambiente conda dedicado
		source activate trimmomatic

	# Análise propriamente dita
	for RUNNAME in $(find ${INPUT_DIR}/. -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort); do
		TRIMMOMATIC_DIR="${OUTPUT_DIR}/${RUNNAME}/trimmomatic"
		TEMP_DIR="$TRIMMOMATIC_DIR/temp"
		if [[ ! -d $TRIMMOMATIC_DIR ]]; then
			mkdir -vp $TRIMMOMATIC_DIR
			mkdir -vp $TEMP_DIR
			echo -e "\nExecutando trimmomatic em ${RUNNAME}...\n"
			# Executa o filtro de qualidade
			trimmomatic PE \
						-threads ${THREADS} \
						#-trimlog "${TRIMMOMATIC_DIR}/${RUNNAME}_trimlog.txt" \
						#-summary ${TRIMMOMATIC_DIR}/${RUNNAME}_summary.txt \
						"${INPUT_DIR}/${RUNNAME}/*_R1*.fastq.gz" "${INPUT_DIR}/${RUNNAME}/*_R2*.fastq.gz" \
						"${TRIMMOMATIC_DIR}/${RUNNAME}_R1.fastq.gz" "${TEMP_DIR}/${RUNNAME}_R1u.fastq.gz" \
						"${TRIMMOMATIC_DIR}/${RUNNAME}_R2.fastq.gz" "${TEMP_DIR}/${RUNNAME}_R2u.fastq.gz" \
						ILLUMINACLIP:"$ADAPTERS":2:30:10 \
						LEADING:3 TRAILING:3 \
						SLIDINGWINDOW:"${SLIDINGWINDOW}" MINLEN:"${MINLEN}"
						
			# Concatena as reads forward e reversar não pareadas para seguir como arquivo singled-end
			zcat "${TEMP_DIR}/${RUNNAME}_R1u.fastq.gz" "${TEMP_DIR}/${RUNNAME}_R2u.fastq.gz" > "${TRIMMOMATIC_DIR}/${RUNNAME}_R1R2u.fastq.gz"
		else
			echo "Dados analisados previamente..."
		fi
	done
	# Inicia o processo de passagem dos dados para o pipeline
	PIPE_DIR="trimmomatic"
