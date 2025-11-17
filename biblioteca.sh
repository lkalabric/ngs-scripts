#function input_validation () {
  # Criar um input_validation.sh a partir do código abaixo
  # Validação dos dados
  # Lê o nome dos arquivos de entrada. O nome curto será o próprio nome da library
  # Renomear os arquivos R1 e R2 para conter o prefixo LIBNAME_ (ex. Bper42_xxxx)
  #INDEX=0
  #for FILE in $(find ${IODIR} -mindepth 1 -type f -name *.fastq.gz -exec basename {} \; | sort); do
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


# Quality control report
# Link: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
function qc () {
	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho para salvamento dos resultados OUTPUT_DIR
		INPUT_DIR=$1
		OUTPUT_DIR="$2/fastqc"
	# Parâmetros padrões e pseronalizados pelo usuário
		source "${HOME}/repos/ngs-scripts/param/fastqc.param"
	# Execução do comando propriamente
	if [[ ! -d "$OUTPUT_DIR" ]]; then
		echo "Criando a pasta dos resultados do fastqc..."
		mkdir -vp "$OUTPUT_DIR"
		echo -e "Executando fastqc nos dados disponíveis em ${INPUT_DIR}...\n"
		fastqc --noextract --nogroup -o ${OUTPUT_DIR} ${INPUT_DIR}/*.fastq.gz
		INPUT_DIR=$OUTPUT_DIR
	else
		echo "Dados analisados previamente..."
	fi
}

# Trimagem de apaptadores de dados de sequencias Illumina
# Link: http://www.usadellab.org/cms/?page=trimmomatic
function trim () {
	# Argumentos dentro da função:
    # $1 caminho de entrada dos dados INPUT_DIR
	# $2 caminho para salvamento dos resultados OUTPUT_DIR
		INPUT_DIR=$1
		OUTPUT_DIR="$2/trimmomatic"	
	# Habilita o trimmomatic instalado em um ambiente conda dedicado
	source activate trimmomatic
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
	IODIR=$OUTPUT_DIR              
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
		echo -e "\nExecutando musket em ${IODIR}...\n"
		
		# New code
		musket -k ${KMER} 536870912 -p ${THREADS} \
			${IODIR}/${LIBNAME}*.fastq \
			-omulti ${MUSKETDIR}/${LIBNAME} -inorder -lowercase
		mv ${MUSKETDIR}/${LIBNAME}.0 ${MUSKETDIR}/${LIBNAME}_R1.fastq
		mv ${MUSKETDIR}/${LIBNAME}.1 ${MUSKETDIR}/${LIBNAME}_R1R2u.fastq
		mv ${MUSKETDIR}/${LIBNAME}.2 ${MUSKETDIR}/${LIBNAME}_R2.fastq
				
		# Original code (somente paired-end data)
		# musket -k ${KMER} 536870912 -p ${THREADS} \
		#	${IODIR}/${LIBNAME}_R1.fastq ${IODIR}/${LIBNAME}_R2.fastq \
		#	-omulti ${MUSKETDIR}/${LIBNAME} -inorder -lowercase
		# mv ${MUSKETDIR}/${LIBNAME}.0 ${MUSKETDIR}/${LIBNAME}_R1.fastq
		# mv ${MUSKETDIR}/${LIBNAME}.1 ${MUSKETDIR}/${LIBNAME}_R2.fastq
	else		
		echo "Dados analisados previamente..."
	fi
  	IODIR=$MUSKETDIR              
}

# Concatenar as reads forward e reverse para extender as reads
# Link: http://ccb.jhu.edu/software/FLASH/
function flash_bper () {
	if [[ ! -d $FLASHDIR ]]; then
		mkdir -vp $FLASHDIR
		echo -e "\nExecutando flash em ${IODIR}...\n"
		flash ${IODIR}/${LIBNAME}_R1.fastq ${IODIR}/${LIBNAME}_R2.fastq \
			-t ${THREADS} -M 100 -o ${LIBNAME} -d ${FLASHDIR} 2>&1 | tee ${FLASHDIR}/${LIBNAME}_flash.log	
		mv ${FLASHDIR}/${LIBNAME}.extendedFrags.fastq ${FLASHDIR}/${LIBNAME}_R1R2e.fastq
		mv ${FLASHDIR}/${LIBNAME}.notCombined_1.fastq ${FLASHDIR}/${LIBNAME}_R1nc.fastq
		mv ${FLASHDIR}/${LIBNAME}.notCombined_2.fastq ${FLASHDIR}/${LIBNAME}_R2nc.fastq
		cp ${MUSKETDIR}/${LIBNAME}_R1R2u.fastq ${FLASHDIR}/
	else
		echo "Dados analisados previamente..."
	fi
  	FLAG=2
	IODIR=$FLASHDIR              
}

# Normalização digital (remove a maioria das sequencias redundantes)
# Link: https://khmer-protocols.readthedocs.io/en/v0.8.2/index.html
function khmer_bper () {
	if [[ ! -d $KHMERDIR ]]; then
		mkdir -vp $KHMERDIR
		echo -e "\nExecutando khmer em ${IODIR}...\n"
		khmer normalize-by-median -M 10000000 -u ${IODIR}/${LIBNAME}*.fastq \
			-s ${KHMERDIR}/${LIBNAME}_graph \
			-R ${KHMERDIR}/${LIBNAME}_report.txt --report-frequency 100000 \
			-o ${KHMERDIR}/${LIBNAME}.fastq
	else
		echo "Dados analisados previamente..."
	fi
  	IODIR=$KHMERDIR              
}

# Assemble reads de novo
# Link: https://github.com/ablab/spades
function spades_bper () {
	if [[ ! -d $SPADESDIR ]]; then
		mkdir -vp $SPADESDIR
		echo -e "\nExecutando spades em ${IODIR}...\n"
		
		# New
		case $FLAG in
		0) 
			echo -e "\nFlag para controle de fluxo da montagem pelo Spades: $FLAG\n"
			spades.py -1 ${IODIR}/*R1*.fastq* -2 ${IODIR}/*R2*.fastq* \
				--only-assembler --careful -o ${SPADESDIR}
			;;
		1) 
			echo -e "\nFlag para controle de fluxo da montagem pelo Spades: $FLAG\n"
			spades.py -1 ${IODIR}/*R1.fastq* -2 ${IODIR}/*R2.fastq* \
				-s ${IODIR}/*R1R2u.fastq* \
				--only-assembler --careful -o ${SPADESDIR}
			;;
		2)
			echo -e "\nFlag para controle de fluxo da montagem pelo Spades: $FLAG\n"
			spades.py -s ${IODIR}/*.fastq \
				--only-assembler --careful -o ${SPADESDIR}
			;;
		*)
			echo -e "Parece que houve algum erro e seus dados não foram montados!\n" 
			exit 7
			if [[ $(ls ${IODIR}/*.fastq* | wc -l) -eq 2 ]]; then
				spades.py -1 ${IODIR}/*R1*.fastq* -2 ${IODIR}/*R2*.fastq* \
					--only-assembler --careful -o ${SPADESDIR}
			else
				spades.py -1 ${IODIR}/*R1.fastq* -2 ${IODIR}/*R2.fastq* \
					-s ${IODIR}/*R1R2u.fastq* \
					--only-assembler --careful -o ${SPADESDIR}
			fi
			;;
		esac
		# Original 
		# Verifica o número de arquivos em ${IODIR}
		#if [[ $(ls ${IODIR}/*.fastq* | wc -l) -eq 1 ]]; then
		#	spades --12 ${IODIR}/${LIBNAME}.fastq \
		#		--only-assembler --careful -o ${SPADESDIR}		
		#else
		#	spades -1 ${IODIR}/*R1*.fastq* -2 ${IODIR}/*R2*.fastq* \
		#	--only-assembler --careful -o ${SPADESDIR}
		#fi
	else
		echo "Dados analisados previamente..."
	fi
 		IODIR=$SPADESDIR              
}

# Assemble contigs end-to-end
# Link: https://github.com/ablab/spades
function spades2_bper () {
	if [[ ! -d $SPADES2DIR ]]; then
		mkdir -vp $SPADES2DIR
		echo -e "\nExecutando spades para montagem as contigs end-to-end em ${IODIR}...\n"
		# Verifica o número de arquivos em ${IODIR}
		spades.py -s ${IODIR}/contigs.fasta \
				--only-assembler --careful -o ${SPADES2DIR}
	else
		echo "Dados analisados previamente..."
	fi
 		IODIR=$SPADES2DIR              
}
