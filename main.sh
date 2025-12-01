#!/bin/bash

# main.sh
# Workflow de bioinformática para análises diversar
# Autor: Luciano Kalabric
# Objetivo: Controle de qualidade
# Controle de versão: 
# Versão 1.0 de 17 NOV 2025 - Programa inicial revisado


# =====================================================
# Validação dos parâmetros passados da linha de comando
# =====================================================
# 1. Parâmetros passados através da linha de comando
WF=$1		# Número da workflow da análise
LIBRARY=$2	# Nome da biblioteca ou caminho de entrada de dados
if [[ $# -ne 2 ]]; then
	echo "❌ ERRO: Faltou o número do workflow ou o nome da biblioteca!"
	echo "Sintaxe: ./main.sh <WF: 1, 2, 3,...> <LIBRARY>"
	exit 0
fi

# ================================================
# Configurações do sistema e instalação de pacotes
# ================================================
# 2. Carregamento do arquivo de biblioteca contendo as funções desenvolvidas para execução do workflow de bioinformática para análise de dados ngs
BIBLIOTECA="${HOME}/repos/ngs-scripts/biblioteca.sh"
if [[ -f "$BIBLIOTECA" ]]; then
	echo "Carregando a biblioteca..."
	source "$BIBLIOTECA"
else
	echo "❌ ERRO: Biblioteca não disponível."
	echo "Verifique com o desenvolvedor do seu pipeline!"
	exit
fi

# 3. Parâmetros configuráveis passados para o script main.sh
# Diretório de parâmetros configuráveis para os diversos scripts
PARAM_DIR="/repos/ngs-scripts/param"
if [[ -f "${HOME}/${PARAM_DIR}/main.param" ]]; then
	echo "Carregando arquivo de configuração..."
	# Neste momento, configura apenas $DATA_DIR e $RESULT_DIR
	source "${HOME}/${PARAM_DIR}/main.param"
else
	echo "❌ ERRO: Arquivo de configuração ${HOME}/${PARAM_DIR}/main.param não disponível."
	echo "Verifique com o desenvolvedor do seu pipeline!"
	exit
fi

# ================
# Entrada de dados
# ================
# 4. Diretório de origem onde os arquivos estão localizados
if [[ ! -d $LIBRARY ]]; then
	# Diretório de entreda padrão baseado no nome da biblioteca
	INPUT_DIR="${HOME}/${DATA_DIR}/${LIBRARY}"
else
	# Diretório de entrada proposto pelo usuário
	INPUT_DIR=$2
	LIBRARY=$(basename $INPUT_DIR)
fi
if [[ ! -d $INPUT_DIR ]]; then
	echo "❌ Erro: Pasta de dados não encontrada!"
	exit 1
else
	echo "✅ Diretório de entrada encontrado em $INPUT_DIR..."
fi


# ==============
# Saída de dados
# ==============
# Diretório de destino onde a nova estrutura de árvore será criada
# Cria o diretório de resultados, caso não exista
echo "Preparando pastas para (re-)análise dos dados..."
OUTPUT_DIR="${HOME}/${RESULTS_DIR}/${LIBRARY}/wf${WF}"
if [[ ! -d "$OUTPUT_DIR" ]]; then
	echo "Criando diretório de saída em $OUTPUT_DIR..."
	mkdir -vp $OUTPUT_DIR
else
	echo "Diretório de saída já existe!"
	read -p "Re-analisar os dados [S-apagar e re-analisa os dados / N-continuar as análises de onde pararam]? " -n 1 -r
	if [[ $REPLY =~ ^[Ss]$ ]]; then
	  # Reseta a pasta de resultados do worflow
		echo -e "\nApagando as pastas e reiniciando as análises..."
		# [[ ! -d $OUTPUT_DIR ]] || mkdir -vp $OUTPUT_DIR && rm -r $OUTPUT_DIR; mkdir -vp $OUTPUT_DIR
		rm -r $OUTPUT_DIR && mkdir -vp $OUTPUT_DIR
	fi
fi

# setup_diretories "${INPUT_DIR} ${RESULTS_DIR}

# Parada para debug
#exit

# ==============
# Main do script
# ==============
# wf1 - system config
# wf2 - consortium/MAGMA
# wf3 - quality control
# wf4 - quality control and trimmomatic

# Define as etapas de cada workflow
# Etapas obrigatórios: basecalling, demux/primer_removal ou demux_headcrop, reads_polishing e algum método de classificação taxonômica
WORKFLOWLIST=(
	'config'
	'magma'
	'fastqc'
	'setup_directories fastqc trim'
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
	eval $CALL_FUNC $INPUT_DIR $OUTPUT_DIR
done

# Gera o log das análises
#log_generator.sh ${LIBRARY} ${WF}
#exit 7
