#!/bin/bash

# main.sh
# Workflow de bioinformática para análises diversar
# Autor: Luciano Kalabric
# Objetivo: Controle de qualidade
# Controle de versão: 
# Versão 1.0 de 17 NOV 2025 - Programa inicial revisado

# Requirements: fastqc

# Funções disponíveis para execução do pipeline
BIBLIOTECA="${HOME}/repos/ngs-scripts/biblioteca.sh"

if [[ -f "$BIBLIOTECA" ]]; then
	echo "Carregando a biblioteca..."
	source $BIBLIOTECA
else
	echo "Biblioteca não disponível. Verifique com o desenvolvedor do seu pipeline!"
	exit
fi

# Parada para debug
exit

# Entrada de dados na linha do comando
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
echo "Preparando pastas para (re-)análise dos dados..."
OUTPUT_DIR="${HOME}/results/${LIBNAME}/wf${WF}"
# Cria a pasta de resultados
if [[ ! -d "${OUTPUT_DIR}" ]]; then
	mkdir -vp ${OUTPUT_DIR}
else
	read -p "Re-analisar os dados [S-apagar e re-analisa os dados / N-continuar as análises de onde pararam]? " -n 1 -r
	if [[ $REPLY =~ ^[Ss]$ ]]; then
	  # Reseta a pasta de resultados do worflow
		echo -e "\nApagando as pastas e reiniciando as análises..."
		[[ ! -d "${OUTPUT_DIR}" ]] || mkdir -vp ${OUTPUT_DIR} && rm -r "${OUTPUT_DIR}"; mkdir -vp "${OUTPUT_DIR}"
	fi
fi

#
# Main do script
#

# wf1 - quality control
# wf2 - naive assembly with no filtering or correction
# wf3 - method with filtering but without error correction
# wf4 - method with filtering and error correction
# wf5 - test flash
# wf6 - test montagem contigs end-to-end

# Define as etapas de cada workflow
# Etapas obrigatórios: basecalling, demux/primer_removal ou demux_headcrop, reads_polishing e algum método de classificação taxonômica
WORKFLOWLIST=(
	'qc'
	'spades_bper'
	'trim_bper spades_bper'
	'trim_bper musket_bper spades_bper'
	'trim_bper musket_bper flash_bper spades_bper'
	'spades_bper spades2_bper'
)

# Validação do WF
if [[ $WF -gt ${#WORKFLOWLIST[@]} ]]; then
	echo "Erro: Workflow não definido!"
	exit 4
fi

# Execução das análises propriamente ditas a partir do workflow selecionado
echo -e "\nExecutando o workflow WF$WF..."

# Índice para o array workflowList 0..n
INDICE=$(expr $WF - 1)
echo "Passos do WF$WF: ${WORKFLOWLIST[$INDICE]}"

# Separa cada etapa do workflow no vetor steps
read -r -a STEPS <<< "${WORKFLOWLIST[$INDICE]}"
for CALL_FUNC in ${STEPS[@]}; do
	echo -e "\nExecutando o passo $CALL_FUNC... "
	eval $CALL_FUNC
done

# Gera o log das análises
#log_generator.sh ${LIBNAME} ${WF}
#exit 7
