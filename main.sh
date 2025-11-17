#!/bin/bash

# main.sh
# Workflow de bioinformática para análises diversar
# Autor: Luciano Kalabric
# Objetivo: Controle de qualidade
# Controle de versão: 
# Versão 1.0 de 17 NOV 2025 - Programa inicial revisado

# Requirements: fastqc

# Entrada de dados
LIBNAME=$1
WF=$2
if [[ $# -ne 2 ]]; then
	echo "Erro: Faltou o nome da biblioteca ou número do workflow!"
	echo "Sintaxe: ./main.sh <LIBRARY> <WF: 1, 2, 3,...>"
	exit 0
fi

# Caminhos dos dados de entrada
RAWDIR="${HOME}/data/${LIBNAME}"
if [[ ! -d $RAWDIR ]]; then
	echo "Erro: Pasta de dados não encontrada!"
	exit 1
fi
INPUT_DIR=$RAWDIR

# Cria o diretório de resultados, caso não exista
OUTPUT_DIR="${HOME}/results/${LIBNAME}"
if [ ! -d "$OUTPUT_DIR" ]; then
    # O '!' inverte a condição (NÃO é um diretório)
    echo "Diretório '$OUTPUT_DIR' não encontrado. Criando..."
    mkdir "$OUTPUT_DIR"
else
    echo "Diretório '$OUTPUT_DIR' já existe. Ignorando a criação."
fi

# Parada para degub do código
exit

# Validação dos dados
# Lê o nome dos arquivos de entreda. O nome curto será o próprio nome da library
# Renomear os arquivos R1 e R2 para conter o prefixo LIBNAME_ (ex. Bper42_xxxx)
INDEX=0
for FILE in $(find ${IODIR} -mindepth 1 -type f -name *.fastq.gz -exec basename {} \; | sort); do
	FULLNAME[$INDEX]=${FILE}
	((INDEX++))
done
SAMPLENAME=$(echo $FULLNAME[0] | cut -d "E" -f 1)
LIBSUFIX=$(echo $LIBNAME | cut -d "_" -f 2)
if [[ $SAMPLENAME -ne $LIBSUFIX ]]; then
	echo "Você copiou os dados errados para a pasta $LIBNAME!"
	exit 3
fi

# Configuração das pastas de saída
echo "Preparando pastas para (re-)análise dos dados..."
RESULTSDIR="${HOME}/ngs-analysis/${LIBNAME}/wf${WF}"
# Cria a pasta de resultados
if [[ ! -d "${RESULTSDIR}" ]]; then
	mkdir -vp ${RESULTSDIR}
else
	read -p "Re-analisar os dados [S-apagar e re-analisa os dados / N-continuar as análises de onde pararam]? " -n 1 -r
	if [[ $REPLY =~ ^[Ss]$ ]]; then
	  # Reseta a pasta de resultados do worflow
		echo -e "\nApagando as pastas e re-iniciando as análises..."
		[[ ! -d "${RESULTSDIR}" ]] || mkdir -vp ${RESULTSDIR} && rm -r "${RESULTSDIR}"; mkdir -vp "${RESULTSDIR}"
	fi
fi
FASTQCDIR="${RESULTSDIR}/FASTQC"
TEMPDIR="${RESULTSDIR}/TEMP"
TRIMMOMATICDIR="${RESULTSDIR}/TRIMMOMATIC"
MUSKETDIR="${RESULTSDIR}/MUSKET"
FLASHDIR="${RESULTSDIR}/FLASH"
KHMERDIR="${RESULTSDIR}/KHMER"
SPADESDIR="${RESULTSDIR}/SPADES"
SPADES2DIR="${RESULTSDIR}/SPADES2"
FLAG=0

# Parâmetro de otimização das análises
KMER=21 # Defaut MAX_KMER_SIZE=28. Se necessário, alterar o Makefile e recompilar
THREADS="$(lscpu | grep 'CPU(s):' | awk '{print $2}' | sed -n '1p')"

# Quality control report
# Foi utilizado para avaliar o sequenciamento e extrair alguns parâmtros para o Trimmomatic
# Link: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
function qc_bper () {
	if [[ ! -d $FASTQCDIR ]]; then
		mkdir -vp $FASTQCDIR
		echo -e "Executando fastqc em ${IODIR}...\n"
		fastqc --noextract --nogroup -o ${FASTQCDIR} ${IODIR}/*.fastq.gz
	else
		echo "Dados analisados previamente..."
	fi
}
