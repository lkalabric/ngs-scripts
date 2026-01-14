function config () {
	# Configuração do sistema e instalação dos pacotes requeridos: fastqc, trimmomatic, mustek
	echo -e "Deseja (Re-)Configurar os pacotes? (Ss/Nn) \c"
	read -r
	echo $REPLY
	if [[ $REPLY =~ ^[Ss]$ ]]; then
		# Instalação dos softwares Linux requeridos (linux_packages.param), se necessário
			install_linux_packages_if_missing
		# Instalação do conda, se necessário
			install_conda_if_missing
		# Instalação dos ambientes e pacotes (conda_packages.param)
			install_conda_packages_if_missing
	fi
}

function install_linux_packages_if_missing () {
	# =================================================================
	# Script: Instalação Condicional de Comandos Ausentes
	# Uso: Este script verifica se um comando está instalado. Se não estiver,
	# tenta instalá-lo usando o gerenciador de pacotes adequado.
	# =================================================================

	# 1. UPDATE & UPGRADE YOUR LINUX DISTRO
	# Before any installation, it is recommended to update and upgrade your Linux Distro
	echo "====================================================="
	echo "Atualizando o Linux para a instalação dos comandos..."
	echo "====================================================="
	sudo apt-get update
	sudo apt list --upgradable
	sudo apt-get upgrade  
	
	# 2. CARREGA A LISTA DE PACOTES A SEREM INSTALADOS
	LINUX_PACKAGES_FILENAME="$HOME/repos/ngs-scripts/param/linux_packages.param"
	if [[ -f "$LINUX_PACKAGES_FILENAME" ]]; then
		echo "Carregando a lista de pacotes para instalação..."
		# source "$LINUX_PACKAGES_FILENAME"
	else
		echo "❌ ERRO: Lista de pacotes não disponível."
		echo "Verifique com o desenvolvedor do seu pipeline!"
		return
	fi
	
	# 3. DETECÇÃO DO GERENCIADOR DE PACOTES
	PACKAGE_MANAGER=""
	INSTALL_CMD=""
	if command -v apt &> /dev/null; then
	    PACKAGE_MANAGER="APT (Debian/Ubuntu)"
	    INSTALL_CMD="sudo apt update && sudo apt install -y "
	# Detecta distros baseadas em Fedora/CentOS/RHEL (DNF/YUM)
	elif command -v dnf &> /dev/null; then
	    PACKAGE_MANAGER="DNF (Fedora/RHEL 8+)"
	    INSTALL_CMD="sudo dnf install -y "
	elif command -v yum &> /dev/null; then
	    PACKAGE_MANAGER="YUM (CentOS/RHEL 7-)"
	    INSTALL_CMD="sudo yum install -y "
	# Detecta distros baseadas em Arch Linux (Pacman)
	elif command -v pacman &> /dev/null; then
	    PACKAGE_MANAGER="Pacman (Arch Linux)"
	    INSTALL_CMD="sudo pacman -S --noconfirm "
	# Detecta distros baseadas em openSUSE (Zypper)
	elif command -v zypper &> /dev/null; then
	    PACKAGE_MANAGER="Zypper (openSUSE)"
	    INSTALL_CMD="sudo zypper install -y "
	else
	    echo "❌ ERRO: Não foi possível identificar um gerenciador de pacotes compatível (apt, dnf, yum, pacman, zypper)."
	    echo "Tente instalar o comando manualmente."
	    exit 1
	fi
	
	# 4. EXECUÇÃO DA INSTALAÇÃO
	echo "Gerenciador de Pacotes Detectado: ${PACKAGE_MANAGER}"
		
	# 5. LER A LISTA DE COMANDOS E INSTALA, SE AUSENTE
	mapfile -t PACKAGES_TO_INSTALL < "${LINUX_PACKAGES_FILENAME}"			
	for PACKAGE_NAME in "${PACKAGES_TO_INSTALL[@]}"; do 
		apt-cache search ^${PACKAGE_NAME}$
		if ! which $PACKAGE_NAME > /dev/null; then
			echo -e "❌ $PACKAGE_NAME is not installed! Install? (y/n) \c"
			read -r
			echo $REPLY
			if [[ $REPLY = "y" ]]; then
				eval "${INSTALL_CMD} ${PACKAGE_NAME}" # sudo apt-get install ${PACKAGE_NAME}
				# Usa o código de saída do comando 'eval' ($?)
				if [ $? -eq 0 ]; then
				    echo "✅ Instalação do '${PACKAGE_NAME}' concluída com sucesso."
				else
				    echo "❌ ERRO: A instalação falhou."
					echo "Verifique se o nome do pacote está correto ou se você tem permissão sudo."
				fi
					echo "`date` sudo apt-get install $PACKAGE_NAME" >> ${HOME}/logs/install_linuxpackages.log
			else
				echo "You can install it anytime!"
			fi
		else
			echo "✅ $PACKAGE_NAME already installed in your Linux Distro!"
		fi
	done
}

function install_conda_if_missing () {
	# =================================================================
	# Script de Instalação Condicional do Miniconda
	# Este script verifica se o ambiente Conda está instalado.
	# Se não estiver, ele baixa e instala o Miniconda.
	# =================================================================
	
	# Variáveis de configuração
	CONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
	CONDA_DOWNLOAD_URL="https://repo.anaconda.com/miniconda/${CONDA_INSTALLER}"
	CONDA_INSTALL_DIR="$HOME/miniconda3"
	
	echo "===================================="
	echo "Verificando a instalação do Conda..."
	echo "===================================="
	# 1. FUNÇÃO PARA VERIFICAR A EXISTÊNCIA DO COMANDO 'conda'
	# O 'command -v' verifica se o comando está no PATH.
	if command -v conda &> /dev/null; then
	    echo "✅ Conda já está instalado e disponível no PATH."
	    # echo "Localização: $(command -v conda)"
	    # echo "Status: Nenhuma ação de instalação necessária."
	    # exit 0
		return
	fi
	
	# 2. SE O CONDA NÃO FOR ENCONTRADO, INICIA A INSTALAÇÃO
	echo "❌ ERRO: Conda não encontrado."
	echo "Iniciando a instalação do Miniconda..."
	
	# 2.1. Verifica a existência do 'curl' ou 'wget' para download
	if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
	    echo "❌ ERRO FATAL: 'curl' ou 'wget' não estão instalados."
	    echo "Não é possível baixar o instalador. Instale um deles e tente novamente."
	    exit 1
	fi
	
	# 2.2. Executa o download
	echo "Baixando o instalador do Miniconda de: ${CONDA_DOWNLOAD_URL}"
	if command -v curl &> /dev/null; then
	    # Usa curl (preferido)
	    curl -o "$CONDA_INSTALLER" "$CONDA_DOWNLOAD_URL"
	elif command -v wget &> /dev/null; then
	    # Fallback para wget
	    wget -O "$CONDA_INSTALLER" "$CONDA_DOWNLOAD_URL"
	fi
	
	if [ $? -ne 0 ]; then
	    echo "ERRO: Falha ao baixar o instalador."
	    rm -f "$CONDA_INSTALLER" # Tenta remover o arquivo parcial
	    exit 1
	fi
	
	# 2.3. Executa a instalação silenciosa
	echo "Executando a instalação não interativa..."
	# Flags de Instalação:
	# -b: Batch mode (não interativo)
	# -p: Define o prefixo de instalação (local onde será instalado)
	bash "$CONDA_INSTALLER" -b -p "$CONDA_INSTALL_DIR"
	
	if [ $? -eq 0 ]; then
	    echo "✅ Instalação do Miniconda concluída com sucesso em: ${CONDA_INSTALL_DIR}"
	else
	    echo "ERRO: O instalador retornou um código de falha."
	    rm -f "$CONDA_INSTALLER"
	    exit 1
	fi
	
	# 2.4. Limpa o instalador
	echo "Removendo o arquivo do instalador: ${CONDA_INSTALLER}"
	rm -f "$CONDA_INSTALLER"
	
	# 3. INICIALIZAÇÃO E CONFIGURAÇÃO
	echo "Configurando o ambiente Shell para o Conda (conda init)..."
	# O comando 'init' adiciona as configurações necessárias ao seu shell profile (~/.bashrc)
	"$CONDA_INSTALL_DIR"/bin/conda init
	
	echo "=================================================="
	echo "INSTALAÇÃO CONCLUÍDA. É necessário REINICIAR o terminal (ou fazer 'source')."
	echo "Para que o comando 'conda' funcione imediatamente nesta sessão:"
	echo "source ~/.bashrc"
	echo "=================================================="
	
	# O script de instalação Bash deve terminar com um status de sucesso
	return
}

function install_conda_packages_if_missing () {
	# =================================================================
	# Script de Configuração de Ambientes Conda Isolados
	# Este script cria um ambiente Conda dedicado para CADA pacote
	# fornecido, garantindo isolamento de dependências.
	#
	# Uso: ./install_isolated_packages.sh <pacote1> <pacote2> ... <pacoteN>
	# Exemplo: ./install_isolated_packages.sh trimmomatic fastqc multiqc
	# =================================================================
	
	# 1. VERIFICAÇÃO INICIAL: Garante que pelo menos um pacote foi fornecido.
	CONDA_PACKAGES_FILENAME="$HOME/repos/ngs-scripts/param/conda_packages.param"
	if [[ -f "$CONDA_PACKAGES_FILENAME" ]]; then
		echo "Carregando a lista de pacotes para instalação..."
	else
		echo "❌ ERRO: Lista de pacotes não disponível."
		echo "Verifique com o desenvolvedor do seu pipeline!"
		return
	fi
		
	#PACKAGES_TO_INSTALL=("$@")
	#if [ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]; then
	#    echo "ERRO: Por favor, forneça pelo menos um nome de pacote Conda para instalar."
	#    echo "Uso: $0 <pacote1> <pacote2> ..."
	#    exit 1
	#fi
	
	# 2. VERIFICAÇÃO DO CONDA: Garante que o comando 'conda' esteja acessível.
	if ! command -v conda &> /dev/null; then
	    echo "❌ ERRO FATAL: O comando 'conda' não foi encontrado."
	    echo "Certifique-se de que o Conda esteja instalado e configurado corretamente."
	    exit 1
	fi
	
	echo "============================================================="
	echo "Iniciando a criação dos ambientes e instalação dos pacotes..."
	echo "============================================================="
	# 3. LOOP PRINCIPAL: Itera sobre cada pacote fornecido.
	mapfile -t PACKAGES_TO_INSTALL < "${CONDA_PACKAGES_FILENAME}"	
	for PACKAGE_NAME in "${PACKAGES_TO_INSTALL[@]}"; do
	    # 3.1 Define o nome do ambiente baseado no nome do pacote
	    ENV_NAME="${PACKAGE_NAME}_env"
		#ENV_NAME=$PACKAGE_NAME
		echo $ENV_NAME
		echo $PACKAGE_NAME
		
	    echo "Criando o ambiente ${ENV_NAME} para instalação do pacote ${PACKAGE_NAME}..."
		
	    # 3.2 Verifica se o ambiente já existe
	    conda info --envs | grep -q "^${ENV_NAME} "
	    ENV_EXISTS=$?
	    INSTALLATION_COMMAND=""
	    if [ ${ENV_EXISTS} -eq 0 ]; then
	        echo "✅ Ambiente '${ENV_NAME}' encontrado."
	        # Ambiente existe: Usa 'install' para garantir que o pacote esteja lá (e atualizado)
	        echo "Garantindo que '${PACKAGE_NAME}' esteja instalado/atualizado..."
	        INSTALLATION_COMMAND="conda init; conda activate \"${ENV_NAME}\";conda install -c bioconda -c conda-forge -c defaults -n \"${ENV_NAME}\" \"${PACKAGE_NAME}\" -y"
	    else
	        echo "❌ Ambiente '${ENV_NAME}' não encontrado."
	        # Ambiente não existe: Usa 'create' para criar e instalar o pacote
	        echo "Criando novo ambiente e instalando '${PACKAGE_NAME}'..."
	        INSTALLATION_COMMAND="conda create -n \"${ENV_NAME}\" -y; conda init; conda activate \"${ENV_NAME}\"; conda install -c bioconda -c conda-forge -c defaults -n \"${ENV_NAME}\" \"${PACKAGE_NAME}\" -y"
	    fi
		
	    # 3.3 Execução do comando
	    # echo "   [DEBUG] Comando: ${INSTALLATION_COMMAND}"
	    eval "${INSTALLATION_COMMAND}"
	    
		# 3.4 Verifica o código de saída da última execução (conda create/install)
	    if [ $? -eq 0 ]; then
	        echo "✅ Instalação/Atualização de '${PACKAGE_NAME}' em '${ENV_NAME}' concluída com sucesso."
	        echo "   Instrução: conda activate ${ENV_NAME}"
	    else
	        echo "❌ ERRO: Falha na instalação de '${PACKAGE_NAME}'. Verifique as mensagens de erro."
	    fi
	done
}

setup_directories () {
    # ----------------------------------------------------
    # Opcional: Descomente a linha abaixo para gerar arquivos de teste
    # generate_sample_files
    # ----------------------------------------------------
    echo "Iniciando a criação da árvore de diretórios em '$OUTPUT_DIR'..."
    
    # 1. Encontra todos os arquivos (-type f) no diretório de dados.
    # 2. Extrai apenas o nome base (basename) de cada arquivo.
    # 3. Usa 'sed' para remover a extensão (tudo após o último ponto).
    # 4. 'sort' e 'uniq' garantem que apenas nomes de base únicos sejam considerados.
    
    find "$INPUT_DIR" -type f -name "$INPUT_TYPE" | \
    while read -r file_name; do
        # 1. Obter nome do arquivo removendo o caminho (e.g., 'data/')
        base_name=$(basename "$file_name")
			
        # 2. Remover a extensão (tudo a partir do último ponto)
        # O comando 'sed' é eficiente aqui para remover '.extensao'
        # unique_base_name=$(echo "$base_name" | sed 's/\.[^.]*$//')
		# echo "unique_base_name: $unique_base_name"	  

		# O BASH é muito eficiente para manipulação de strings.
		# Usamos '%%.*' para remover a maior correspondência da direita para a esquerda (a extensão)
		# e '%%_R*' para remover a maior correspondência da direita para a esquerda (o "_R" e tudo o que vier depois).

		# 3. Remove a extensão (e.g., '.fastq.gz')
		unique_base_name="${base_name%%.*}"
		
		# 4. Remove o padrão "_R" e tudo o que vier depois
		# (e.g., de "Minha_Amostra_R1" remove "_R1")
		unique_base_name="${unique_base_name%%_R*}"
		
        # Omitir nomes vazios (caso haja diretórios ocultos ou de sistema)
        if [ -n "$unique_base_name" ]; then
            # Imprimir o nome de base único para fins de rastreamento
            echo "$unique_base_name"
        fi
    done | \
    sort | uniq | \
    while read -r final_unique_name; do
    	# 5. Criar o diretório correspondente em RESULTS_DIR
        mkdir -p "$OUTPUT_DIR/$final_unique_name"
        echo "  -> Diretório criado: $OUTPUT_DIR/$final_unique_name"
    done
    echo "Processo concluído!"
    echo "Nova estrutura de diretórios criada em '$OUTPUT_DIR'."
}

# Magma
# A pipeline for comprehensive genomic analyses of Mycobacterium tuberculosis with a focus on clinical decision making as well as research
function magma () {
	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho para salvamento dos resultados OUTPUT_DIR
	INPUT_DIR=$1
	# OUTPUT_DIR="magma-results & work" Diretórios padrões  
	# --- Análise dos dados de teste remotamente ---
	# Na Fiocruz isso não roda por conta do acesso a internet 
    nextflow run 'https://github.com/TORCH-Consortium/MAGMA' \
         -profile docker,low_memory \
         -r v2.2.2 \
         -params-file $INPUT_DIR/my_parameters_3_local.yml
}

#function input_validation () {
  # Criar um input_validation.sh a partir do código abaixo
  # Validação dos dados
  # Lê o nome dos arquivos de entrada. O nome curto será o próprio nome da library
  # Renomear os arquivos R1 e R2 para conter o prefixo LIBNAME_ (ex. Bper42_xxxx)
  #INDEX=0
  #for FILE in $(find ${INPUT_DIR} -mindepth 1 -type f -name *.fastq.gz -exec basename {} \; | sort); do
  #	FULLNAME[$INDEX]=${FILE}
  #	((INDEX++))
  #done
  #SAMPLENAME=$(echo $FULLNAME[0] | cut -d "E" -f 1)
  #LIBSUFIX=$(echo $LIBNAME | cut -d "_" -f 2)
  #if [[ $SAMPLENAME -ne $LIBSUFIX ]]; then
  #    echo "Você copiou os dados errados para a pasta $LIBNAME!"
  #    exit 3
  #fi
#}

function organize_files () {
	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
		INPUT_DIR=$1

	# ==============================================================================
	# Script: organizar_arquivos.sh
	# Descrição: Lê arquivos de um diretório, identifica a raiz do nome e os organiza
	#            em pastas baseadas nessa raiz.
	# ==============================================================================
	# Diretório alvo (padrão é o diretório atual se nenhum for passado)
	TARGET_DIR="$INPUT_DIR"

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
}

function read_dir () {
	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho de saída dos resultados OUTPUT_DIR
	INPUT_DIR=$1
	OUTPUT_DIR=$2
	echo "Entrada: $INPUT_DIR"
	echo "Saída: $OUTPUT_DIR"
	
	for SAMPLE in $(find $INPUT_DIR/. -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort); do
		base_name=$(basename "$SAMPLE")
		echo "Sample: $SAMPLE"
		echo "Basename: $base_name"
		mkdir $OUTPUT_DIR/$base_name
		cp $INPUT_DIR/$base_name/* $OUTPUT_DIR/$base_name/
	done
}


function fastqc () {
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
	for SAMPLE in $(find $INPUT_DIR/. -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort); do
		base_name=$(basename "$SAMPLE")
		if [[ -n "$base_name" && ! -d "$OUTPUT_DIR/$base_name/fastqc" ]]; then
			echo "Criando a pasta de saída nos dados ${base_name}..."
			FASTQC_DIR="$OUTPUT_DIR/$base_name/fastqc"
			mkdir -vp $FASTQC_DIR
			echo -e "Executando o fastqc nos dados disponíveis em ${base_name}...\n"
			fastqc --noextract --nogroup -o ${FASTQC_DIR} ${INPUT_DIR}/${base_name}/*		
		else
			echo "Dados analisados previamente..."
		fi
	done
	
	find "$OUTPUT_DIR" -type d | \
    while read -r INPUT_DIR; do
        # 1. Obter nome do arquivo removendo o caminho (e.g., 'data/')
        base_name=$(basename "$INPUT_DIR")
		# OUTPUT_DIR="$base_name/fastqc"      
		# Execução do comando propriamente
		if [[ -n "$base_name" && ! -d "$FASTQC_DIR" ]]; then
			echo "Criando a pasta dos resultados do fastqc..."
			mkdir -vp "$FASTQC_DIR"
			echo -e "Executando fastqc nos dados disponíveis em ${INPUT_DIR}...\n"
			fastqc --noextract --nogroup -o ${OUTPUT_DIR} ${INPUT_DIR}/${INPUT_TYPE}			
		else
			echo "Dados analisados previamente..."
		fi
	done
	$INPUT_DIR=$FASTQC_DIR
}

function trim () {
	# Trimagem de apaptadores de dados de sequencias Illumina
	# Link: http://www.usadellab.org/cms/?page=trimmomatic

	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho para salvamento dos resultados OUTPUT_DIR
		INPUT_DIR=$1
		OUTPUT_DIR="$2/trimmomatic"
		TEMP_DIR="$OUTPUT_DIR/temp"
	echo "Input: ${INPUT_DIR}"
	echo "Output: ${OUTPUT_DIR}"
	# Habilita o trimmomatic instalado em um ambiente conda dedicado
	source activate trimmomatic_env
	if [[ ! -d $OUTPUT_DIR ]]; then
		mkdir -vp $OUTPUT_DIR
		mkdir -vp $TEMP_DIR
		echo -e "\nExecutando trimmomatic em ${INPUT_DIR}...\n"
		# Executa o filtro de qualidade
		trimmomatic PE -threads ${THREADS} -trimlog ${OUTPUT_DIR}/${LIBNAME}_trimlog.txt \
					-summary ${OUTPUT_DIR}/${LIBNAME}_summary.txt \
					${INPUT_DIR}/*.fastq* \
					${OUTPUT_DIR}/${LIBNAME}_R1.fastq ${TEMP_DIR}/${LIBNAME}_R1u.fastq \
					${OUTPUT_DIR}/${LIBNAME}_R2.fastq ${TEMP_DIR}/${LIBNAME}_R2u.fastq \
					SLIDINGWINDOW:4:20 MINLEN:35
		# Concatena as reads forward e reversar não pareadas para seguir como arquivo singled-end
		cat ${TEMP_DIR}/${LIBNAME}_R1u.fastq ${TEMP_DIR}/${LIBNAME}_R2u.fastq > ${OUTPUT_DIR}/${LIBNAME}_R1R2u.fastq
	else
		echo "Dados analisados previamente..."
	fi
  	FLAG=1
	INPUT_DIR=$OUTPUT_DIR              
}

# Correção de erros
# Link: https://musket.sourceforge.net/homepage.htm
function musket () {
	# Argumentos dentro da função:
	# $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho para salvamento dos resultados OUTPUT_DIR
	INPUT_DIR=$1
	OUTPUT_DIR="$2/musket"
	if [[ ! -d $MUSKETDIR ]]; then
		mkdir -vp $MUSKETDIR
		echo -e "\nExecutando musket em ${INPUT_DIR}...\n"
		
		# New code
		musket -k ${KMER} 536870912 -p ${THREADS} \
			${INPUT_DIR}/${LIBNAME}*.fastq \
			-omulti ${MUSKETDIR}/${LIBNAME} -inorder -lowercase
		mv ${MUSKETDIR}/${LIBNAME}.0 ${MUSKETDIR}/${LIBNAME}_R1.fastq
		mv ${MUSKETDIR}/${LIBNAME}.1 ${MUSKETDIR}/${LIBNAME}_R1R2u.fastq
		mv ${MUSKETDIR}/${LIBNAME}.2 ${MUSKETDIR}/${LIBNAME}_R2.fastq
				
		# Original code (somente paired-end data)
		# musket -k ${KMER} 536870912 -p ${THREADS} \
		#	${INPUT_DIR}/${LIBNAME}_R1.fastq ${INPUT_DIR}/${LIBNAME}_R2.fastq \
		#	-omulti ${MUSKETDIR}/${LIBNAME} -inorder -lowercase
		# mv ${MUSKETDIR}/${LIBNAME}.0 ${MUSKETDIR}/${LIBNAME}_R1.fastq
		# mv ${MUSKETDIR}/${LIBNAME}.1 ${MUSKETDIR}/${LIBNAME}_R2.fastq
	else		
		echo "Dados analisados previamente..."
	fi
  	INPUT_DIR=$MUSKETDIR              
}

# Concatenar as reads forward e reverse para extender as reads
# Link: http://ccb.jhu.edu/software/FLASH/
function flash_bper () {
	if [[ ! -d $FLASHDIR ]]; then
		mkdir -vp $FLASHDIR
		echo -e "\nExecutando flash em ${INPUT_DIR}...\n"
		flash ${INPUT_DIR}/${LIBNAME}_R1.fastq ${INPUT_DIR}/${LIBNAME}_R2.fastq \
			-t ${THREADS} -M 100 -o ${LIBNAME} -d ${FLASHDIR} 2>&1 | tee ${FLASHDIR}/${LIBNAME}_flash.log	
		mv ${FLASHDIR}/${LIBNAME}.extendedFrags.fastq ${FLASHDIR}/${LIBNAME}_R1R2e.fastq
		mv ${FLASHDIR}/${LIBNAME}.notCombined_1.fastq ${FLASHDIR}/${LIBNAME}_R1nc.fastq
		mv ${FLASHDIR}/${LIBNAME}.notCombined_2.fastq ${FLASHDIR}/${LIBNAME}_R2nc.fastq
		cp ${MUSKETDIR}/${LIBNAME}_R1R2u.fastq ${FLASHDIR}/
	else
		echo "Dados analisados previamente..."
	fi
  	FLAG=2
	INPUT_DIR=$FLASHDIR              
}

# Normalização digital (remove a maioria das sequencias redundantes)
# Link: https://khmer-protocols.readthedocs.io/en/v0.8.2/index.html
function khmer_bper () {
	if [[ ! -d $KHMERDIR ]]; then
		mkdir -vp $KHMERDIR
		echo -e "\nExecutando khmer em ${INPUT_DIR}...\n"
		khmer normalize-by-median -M 10000000 -u ${INPUT_DIR}/${LIBNAME}*.fastq \
			-s ${KHMERDIR}/${LIBNAME}_graph \
			-R ${KHMERDIR}/${LIBNAME}_report.txt --report-frequency 100000 \
			-o ${KHMERDIR}/${LIBNAME}.fastq
	else
		echo "Dados analisados previamente..."
	fi
  	INPUT_DIR=$KHMERDIR              
}

# Assemble reads de novo
# Link: https://github.com/ablab/spades
function spades_bper () {
	if [[ ! -d $SPADESDIR ]]; then
		mkdir -vp $SPADESDIR
		echo -e "\nExecutando spades em ${INPUT_DIR}...\n"
		
		# New
		case $FLAG in
		0) 
			echo -e "\nFlag para controle de fluxo da montagem pelo Spades: $FLAG\n"
			spades.py -1 ${INPUT_DIR}/*R1*.fastq* -2 ${INPUT_DIR}/*R2*.fastq* \
				--only-assembler --careful -o ${SPADESDIR}
			;;
		1) 
			echo -e "\nFlag para controle de fluxo da montagem pelo Spades: $FLAG\n"
			spades.py -1 ${INPUT_DIR}/*R1.fastq* -2 ${INPUT_DIR}/*R2.fastq* \
				-s ${INPUT_DIR}/*R1R2u.fastq* \
				--only-assembler --careful -o ${SPADESDIR}
			;;
		2)
			echo -e "\nFlag para controle de fluxo da montagem pelo Spades: $FLAG\n"
			spades.py -s ${INPUT_DIR}/*.fastq \
				--only-assembler --careful -o ${SPADESDIR}
			;;
		*)
			echo -e "Parece que houve algum erro e seus dados não foram montados!\n" 
			exit 7
			if [[ $(ls ${INPUT_DIR}/*.fastq* | wc -l) -eq 2 ]]; then
				spades.py -1 ${INPUT_DIR}/*R1*.fastq* -2 ${INPUT_DIR}/*R2*.fastq* \
					--only-assembler --careful -o ${SPADESDIR}
			else
				spades.py -1 ${INPUT_DIR}/*R1.fastq* -2 ${INPUT_DIR}/*R2.fastq* \
					-s ${INPUT_DIR}/*R1R2u.fastq* \
					--only-assembler --careful -o ${SPADESDIR}
			fi
			;;
		esac
		# Original 
		# Verifica o número de arquivos em ${INPUT_DIR}
		#if [[ $(ls ${INPUT_DIR}/*.fastq* | wc -l) -eq 1 ]]; then
		#	spades --12 ${INPUT_DIR}/${LIBNAME}.fastq \
		#		--only-assembler --careful -o ${SPADESDIR}		
		#else
		#	spades -1 ${INPUT_DIR}/*R1*.fastq* -2 ${INPUT_DIR}/*R2*.fastq* \
		#	--only-assembler --careful -o ${SPADESDIR}
		#fi
	else
		echo "Dados analisados previamente..."
	fi
 		INPUT_DIR=$SPADESDIR              
}

# Assemble contigs end-to-end
# Link: https://github.com/ablab/spades
function spades2_bper () {
	if [[ ! -d $SPADES2DIR ]]; then
		mkdir -vp $SPADES2DIR
		echo -e "\nExecutando spades para montagem as contigs end-to-end em ${INPUT_DIR}...\n"
		# Verifica o número de arquivos em ${INPUT_DIR}
		spades.py -s ${INPUT_DIR}/contigs.fasta \
				--only-assembler --careful -o ${SPADES2DIR}
	else
		echo "Dados analisados previamente..."
	fi
 		INPUT_DIR=$SPADES2DIR              
}
