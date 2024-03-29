#!/bin/bash

# script: metagenomics8.sh
# autores: Alessandra Gonzalez <alessandragonzalez13@hotmail.com>, Laise de Moraes <laisepaixao@live.com> & Luciano Kalabric <luciano.kalabric@fiocruz.br>
# instituição: Oswaldo Cruz Foundation, Gonçalo Moniz Institute, Bahia, Brazil
# criação: 09 JUN 2022
# última atualização: 19 JAN 2023
# versão 5: modulariza e personaliza as workflows a partir do uso de funções
# versão 6: cria a função filter_by_starttime
# versão 7: re-organiza o output das analises de cada workflows e remove redundâncias
# versão 8: criação do módulo coverage

#
# Descrição de cada função disponível para construção dos workflows
#
# IMPORTANTE: Antes de construir a workflow revificar se o I/O é compatível entre a função anterior e a seguinte
# Neste momento, reads_polishing deve conectar a saída dos filtros à análise de classificação taxonômica
# setup_env
# sequencing_summary1/GREP 			(input: .fast5; output: STDOUT)
# basecalling/GUPPY_BASECALLER			(input: .fast5; output: sequencing_summary.txt, barcode_summary.txt, .fastq)
# sequencing_summary2/PYCOQC			(input: sequencing_summary.txt, barcode_summary.txt; output: .html)
# demux/GUPPY_BARCODER				(input: .fastq; output: .fastq, .log)
	# primer_removal/CUTADAPT		(input: .fastq; output: .fastq, .log)
# demux_headcrop/GUPPY_BARCODER			(input: .fastq; output: .fastq, .log)
# filter_by_starttime/GREP			(input: .fastq; output: .fastq, .log)
# qc_filter1/NANOFILT				(input: .fastq; output: .fastq, .log)
# qc_filter2/PRINSEQ				(input: .fastq; output: .fastq, .log)
# human_filter1/MINIMAP/SAMTOOLS		(input: .fastq; output: .fastq, .log)
# human_filter2/GMAPL				(input: .fastq; output: .fastq, .log)
# reads_polishing/MINIMAP/SAMTOOLS/RACON	(input: .fastq; output: .fasta, .log)
# reads_level
	# blastn_local/BLASTN			(input: .fasta, output: .blastn, .log)
		# blast_report.sh		(input: .blastn, outpu: .blastnreport)
	# kraken_local/KRAKEN2			(input: .fasta, output: _report.txt, _output.txt)	
		# kraken2_quick_report.sh	(input: _report.txt, _quick_report.txt)
	# coverage/SAMTOOLS COVERAGE		(input: .fasta; output: _fastcov.txt) Em teste!
# assembly/SPADES.PY				(input: .fasta; output: .fasta)
# contigs_level
	# blastncontig_local/BLASTN		(input: .fasta, output: .blastn, .log)
		# blastn_report.sh		(input: .blastn, outpu: .blastnreport)
	# krakencontif_local/KRAKEN2		(input: .fasta, output: _report.txt, _output.txt)	
		# kraken2_quick_report.sh	(input: _report.txt, _quick_report.txt)
# instalacao

#
# Validação da entrada de dados na linha de comando
#
WF=$1		# Workflow de bioinformatica 1, 2 ou 3
MODEL=$2	# Modelo de basecalling fast hac sup
RUNNAME=$3 	# Nome do dado passado na linha de comando
if [[ $# -eq 0 ]]; then
	echo "Falta o nome dos dados, número do worflow ou modelo Guppy Basecaller!"
	echo "Sintáxe: ./metagenomics8.sh <WF: 1, 2, 3, 3_filter...> <MODELO: fast, hac, sup> <LIBRARY>"
	exit 0
fi

function exists_in_list () {
    LIST=$1
    DELIMITER=$2
    VALUE=$3
    LIST_WHITESPACES=`echo $LIST | tr "$DELIMITER" " "`
    for x in $LIST_WHITESPACES; do
        if [ "$x" = "$VALUE" ]; then
            return 0
        fi
    done
    return 1
}

# Testa se o workflow existe
LIST_OF_WFS="1 2 3 3_filter instalacao"
if ! exists_in_list "$LIST_OF_WFS" " " $WF; then
	echo -e "WF não indisponível. Usar: $LIST_OF_WFS!\n"
	exit 0
else
	# Testa se o modelo para guppy_basecalling usado existe
	if [ $WF != "instalacao" ]; then
		LIST_OF_MODELS="fast hac sup"
		if ! exists_in_list "$LIST_OF_MODELS" " " $MODEL; then
			echo -e "Modelo $MODEL indisponível. Usar: $LIST_OF_MODELS.\n"
			exit 0
		fi
		# Caminho de INPUT dos dados .fast5
		RAWDIR="${HOME}/data/${RUNNAME}"
		# Teste se os dados existem
		if [ ! -d $RAWDIR ]; then
			echo "Pasta de dados ${RUNNAME} não encontrada!"
			exit 0
		fi
	else
		echo -e "Instalação/atualização dos softwares\n"
	fi
fi

function setup_env () {
	# Verifica se os ambientes conda ngs ou bioinfo foram criados e ativa um dos ambientes
	
	# Tipicamente, instalamos todos os pacotes em um destes ambientes, mas, recentemente, estamos
	# mudando isso para ter cada pacote em seu próprio ambiente conda por questões de compatibilidade
	# com o Python!
	if { conda env list | grep 'ngs'; } >/dev/null 2>&1; then
		source activate ngs
		conda update --all
	else
		if { conda env list | grep 'bioinfo'; } >/dev/null 2>&1; then
			source activate bioinfo
			conda update --all
		else
			echo "Ambiente conda indisponível!"
			exit 0
		fi
	fi

	# Declaração das variáveis
	
	# Caminho de INPUT dos bancos de dados
	HUMANREFDIR="${HOME}/data/GRCh38"
	REFSEQDIR="${HOME}/data/REFSEQ"
	BLASTDBDIR="${HOME}/data/BLAST_DB"
	KRAKENDBDIR="${HOME}/data/KRAKEN2_DB" # Substituir pelo nosso banco de dados se necessário KRAKEN2_USER_DB
	REFGENDIR="${HOME}/data/REFGEN"

	# Caminhos de OUTPUT das análises
	echo "Preparando pastas para (re-)análise dos dados..."
	RESULTSDIR="${HOME}/ngs-analysis/${RUNNAME}_${MODEL}"
	# Cria a pasta de resultados
	if [[ ! -d "${RESULTSDIR}" ]]; then
		mkdir -vp ${RESULTSDIR}
		mkdir -vp ${RESULTSDIR}/wf${WF}
	else
		read -p "Re-analisar os dados [S-apagar e re-analisa os dados / N-continuar as análises de onde pararam]? " -n 1 -r
		if [[ $REPLY =~ ^[Ss]$ ]]; then
			# Reseta a pasta de resultados do worflow
			echo "Apagando as pastas e re-iniciando as análises..."
			rm -r ${RESULTSDIR}
			mkdir -vp ${RESULTSDIR}
			mkdir -vp ${RESULTSDIR}/wf${WF}
		fi
	fi
	BASECALLDIR="${RESULTSDIR}/BASECALL"
	DEMUXDIR="${RESULTSDIR}/wf${WF}/DEMUX"
	DEMUXCATDIR="${RESULTSDIR}/wf${WF}/DEMUX_CAT"
	FILTERBYSTARTTIMEDIR="${RESULTSDIR}/wf${WF}/FILTERBYSTARTTIME"
	QCFILTERSDIR="${RESULTSDIR}/wf${WF}/QC_FILTERS"
	CUTADAPTDIR="${RESULTSDIR}/wf${WF}/CUTADAPT"
	NANOFILTDIR="${RESULTSDIR}/wf${WF}/NANOFILT"
	PRINSEQDIR="${RESULTSDIR}/wf${WF}/PRINSEQ"
	HUMANFILTERDIR1="${RESULTSDIR}/wf${WF}/HUMANFILTER1"
	HUMANFILTERDIR2="${RESULTSDIR}/wf${WF}/HUMANFILTER2"
	READSLEVELDIR="${RESULTSDIR}/wf${WF}/READS_LEVEL"
	KRAKENREADSDIR="${READSLEVELDIR}/KRAKEN"
	BLASTNREADSDIR="${READSLEVELDIR}/BLASTN"
	COVERAGEDIR="${READSLEVELDIR}/COVERAGE"
	MAPPINGDIR="${READSLEVELDIR}/MAPPING"
	CONTIGSLEVELDIR="${RESULTSDIR}/wf${WF}/CONTIGS_LEVEL"
	KRAKENCONTIGSDIR="${CONTIGSLEVELDIR}/KRAKEN"
	BLASTNCONTIGSDIR="${CONTIGSLEVELDIR}/BLASTN"

	# Pausa a execução para debug
	# read -p "Press [Enter] key to continue..."

	# Parâmetros de qualidade mínima
	# Default Fast min_qscore=8; Hac min_qscore=9; Sup min_qscore=10
	QSCORE=9
	LENGTH=100

	# Parâmetro de otimização minimap2, samtools, racon e kraken2
	THREADS="$(lscpu | grep 'CPU(s):' | awk '{print $2}' | sed -n '1p')"

	# Parâmetros minimap2 
	# wget http://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_38/GRCh38.p13.genome.fa.gz -P ${HUMANREFDIR}
	echo "Gerando arquivos de índices para mapeamento no genoma humano..."
	HUMANREFSEQ="${HUMANREFDIR}/GRCh38.p13.genome.fa.gz"
	HUMANREFMMI="${HUMANREFDIR}/GRCh38.p13.genome.mmi"
	source activate minimap2
	# Cria o arquivo índice do genoma humano para reduzir o tempo de alinhamento
	if [ ! -f $HUMANREFMMI ]; then
		minimap2 -d $HUMANREFMMI $HUMANREFSEQ
	fi
	# Cria o arquivo índice das sequencias referencias para mapeamento das reads pelo minimap2
	echo "Gerando arquivos de índices para mapeamento em genomas virais de referencia..."
	for j in $(find ${REFGENDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
		REFGENFASTA="${REFGENDIR}/${j}.fasta"
		REFGENMMI="${REFGENDIR}/${j}.mmi"
		[ ! -f $REFGENMMI ] && minimap2 -d $REFGENMMI $REFGENFASTA
	done  
}

#
# Funções que constituem os passos do pipeline
#
function sequencing_summary1 () {
	# Sumario do sequenciamento (dados disponíveis no arquivo report*.pdf)
	echo "Sumário da corrida"
	echo "Total files:"
	ls $(find ${RAWDIR} -type f -name "*.fast5" -exec dirname {} \;) | wc -l
	echo "Total reads:"
	# h5ls "$(find ${RAWDIR} -type f -name "*.fast5" -exec dirname {} \;)"/*.fast5 | wc -l
}

function basecalling () {
	# Basecalling (comum a todos workflows)
	# Parâmetros Guppy basecaller (ONT)
	CONFIG="dna_r9.4.1_450bps_${MODEL}.cfg" #dna_r9.4.1_450bps_fast.cfg dna_r9.4.1_450bps_hac.cfg dna_r9.4.1_450bps_sup.cfg
	# Parâmetros para otimização do Guppy basecaller (ONT) obtidos pelo benckmark utilizadando o LAPTOP-Yale
	case $MODEL in
	  fast)
	    GPUPERDEVICE=4		
	    CHUNCKSIZE=1000		
	    CHUNKPERRUNNER=50
	  ;;
	  hac)
	    GPUPERDEVICE=12		
	    CHUNCKSIZE=2000		
	    CHUNKPERRUNNER=256
	  ;;
	  sup)
	    GPUPERDEVICE=12		
	    CHUNCKSIZE=1000		
	    CHUNKPERRUNNER=256
	  ;;
	  *)
	    GPUPERDEVICE=4		
	    CHUNCKSIZE=1000		
	    CHUNKPERRUNNER=50
	  ;;
	esac
	# Cria a pasta BASECALLDIR e faz o basecalling
	if [ ! -d $BASECALLDIR ]; then
		mkdir -vp $BASECALLDIR
		echo -e "Executando guppy_basecaller...\n"
		# Comando para guppy_basecaller usando GPU
		guppy_basecaller -r -i ${RAWDIR} -s "${BASECALLDIR}" -c ${CONFIG} -x auto --min_qscore ${QSCORE} --gpu_runners_per_device ${GPUPERDEVICE} --chunk_size ${CHUNCKSIZE} --chunks_per_runner ${CHUNKPERRUNNER} --verbose_logs
	else
		echo "Usando dados BASECALL analisados previamente..."
	fi
  IODIR=$BASECALLDIR
}

# Para debug
# if false; then # Desvio para execução rápida
# fi # Fim do desvio para execução rápida

function demux () {
	# Demultiplex, adapter removal & sem headcrop 18 para uso do cutadapt
	# Parâmetros Guppy barcoder (ONT)
	ARRANGEMENTS="barcode_arrs_nb12.cfg barcode_arrs_nb24.cfg"
	if [ ! -d $DEMUXDIR ]; then
		mkdir -vp $DEMUXDIR
		echo -e "Executando guppy_barcoder em ${IODIR}...\n"
		guppy_barcoder -r -i "${IODIR}/pass" -s ${DEMUXDIR} --arrangements_files ${ARRANGEMENTS} --require_barcodes_both_ends  --detect_mid_strand_barcodes --trim_barcodes  
		# Renomeei a pasta contendo as reads unclassified para barcode00 para análise
		# [ -d "${DEMUXDIR}/unclassified" ] && mv "${DEMUXDIR}/unclassified" "${DEMUXDIR}/barcode00"
		# Concatena todos arquivos .fastq de cada barcode em um arquivo .fastq único
		[ ! -d ${DEMUXCATDIR} ] && mkdir -vp ${DEMUXCATDIR}
		for i in $(find ${DEMUXDIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			[ -d "${DEMUXDIR}/${i}" ] && cat ${DEMUXDIR}/${i}/*.fastq > "${DEMUXCATDIR}/${i}.fastq"
			# Gera o arquivo de log
			# echo "${i} $(grep -c "runid" ${DEMUXDIR}/${i}/*.fastq)" >> ${DEMUXDIR}/passed_reads.log
			echo "${i} `echo $(cat ${DEMUXDIR}/${i}/*.fastq|wc -l)/4|bc`"  >> ${DEMUXDIR}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${DEMUXCATDIR}/${i}.fastq)" >> ${DEMUXCATDIR}/passed_reads.log
			echo "${i} `echo $(cat ${DEMUXCATDIR}/${i}.fastq|wc -l)/4|bc`"  >> ${DEMUXCATDIR}/passed_reads.log
		done
	else
		echo "Usando dados DEMUX_CAT analisados previamente..."
	fi
  IODIR=$DEMUXCATDIR  
}

function primer_removal () {
	# Remoção dos primers
	if [ ! -d $CUTADAPTDIR ]; then
		mkdir -vp ${CUTADAPTDIR}
		# [ ! -d ${CUTADAPTDIR} ] && mkdir -vp ${CUTADAPTDIR}	
		PRIMER="GTTTCCCACTGGAGGATA"
		echo -e "executando cutadapt em ${IODIR}...\n"
		source activate cutadapt
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			cutadapt -g ${PRIMER} -e 0.2 --discard-untrimmed -o "${CUTADAPTDIR}/${i}.fastq" "${DEMUXCATDIR}/${i}.fastq"
			# echo -e "\nResultados ${i} $(grep -c "runid" ${CUTADAPTDIR}/${i}.fastq | cut -d : -f 2 | awk '{s+=$1} END {printf "%.0f\n",s}')"
			# Gera o arquivo de log
			echo "${i} `echo $(cat ${CUTADAPTDIR}/${i}.fastq|wc -l)/4|bc`"  >> ${CUTADAPTDIR}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${CUTADAPTDIR}/${i}.fastq)" >> ${CUTADAPTDIR}/passed_reads.log
		done
		conda deactivate
	else
		echo "Usando dados CUTADAPT analisados previamente..."
	fi
  IODIR=$CUTADAPTDIR
}

function demux_headcrop () {
	# Demultiplex, adapter removal com headcrop 18 sem uso do cutadapt
	# Parâmetros Guppy barcoder (ONT)
	TRIMADAPTER=18
	ARRANGEMENTS="barcode_arrs_nb12.cfg barcode_arrs_nb24.cfg"
	if [ ! -d $DEMUXDIR ]; then
		mkdir -vp $DEMUXDIR
		echo -e "Executando guppy_barcoder para demux_headcrop em ${IODIR}...\n"
		guppy_barcoder -r -i "${IODIR}/pass" -s ${DEMUXDIR} --arrangements_files ${ARRANGEMENTS} --require_barcodes_both_ends  --detect_mid_strand_barcodes --trim_barcodes --num_extra_bases_trim ${TRIMADAPTER}
		# Renomeia a pasta contendo as reads unclassified para barcode00 para análise
		# [ -d "${DEMUXDIR}/unclassified" ] && mv "${DEMUXDIR}/unclassified" "${DEMUXDIR}/barcode00"
		# Concatena todos arquivos .fastq de cada barcode em um arquivo .fastq único
		[ ! -d ${DEMUXCATDIR} ] && mkdir -vp ${DEMUXCATDIR}
		for i in $(find ${DEMUXDIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			[ -d "${DEMUXDIR}/${i}" ] && cat ${DEMUXDIR}/${i}/*.fastq > "${DEMUXCATDIR}/${i}.fastq"
			# Gera o arquivo de log
			echo "${i} `echo $(cat ${DEMUXDIR}/${i}/*.fastq|wc -l)/4|bc`"  >> ${DEMUXDIR}/passed_reads.log
			echo "${i} `echo $(cat ${DEMUXCATDIR}/${i}.fastq|wc -l)/4|bc`"  >> ${DEMUXCATDIR}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${DEMUXCATDIR}/${i}.fastq)" >> ${DEMUXCATDIR}/passed_reads.log
		done
	else
		echo "Usando dados DEMUX_CAT analisados previamente..."
	fi
  IODIR=$DEMUXCATDIR
}

function filter_by_start_time () {
	if [ ! -d "${FILTERBYSTARTTIMEDIR}" ]; then
		mkdir -vp "${FILTERBYSTARTTIMEDIR}"
		# Define os STAR_TIME de interesse
		declare -a START_TIME=(01 02 04 08 12 16 24 all)
		# Define as expressões regulares de cada START_TIME para busca
		declare -a REGEXP=("(0+[0-1])" "(0+[0-2])" "(0+[0-4])" "(0+[0-8])" "(0+[0-9]|1+[0-2])" "(0+[0-9]|1+[0-6])" "(0+[0-9]|1+[0-9]|2+[0-4])" "..")
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
	    		echo -e "\nContando as reads do arquivo ${DEMUXCATDIR}/${i}.fastq..."
			echo "Todos - $(grep ${RUNNAME} ${DEMUXCATDIR}/${i}.fastq | wc -l)" >> ${FILTERBYSTARTTIMEDIR}/${i}_filterlog.txt
			for ((j=0; j<=7; j++)); do
				echo -e "\nExecutando filter_by_start_time ${START_TIME[${j}]}..."
				# Filtar as reads por start_time
				egrep -A3 "start_time=..........T${REGEXP[${j}]}" "${DEMUXCATDIR}/${i}.fastq" > "${FILTERBYSTARTTIMEDIR}/${i}_${START_TIME[${j}]}.fastq"
				echo -e "\nContando as reads do arquivo "${FILTER_BY_START_TIMEDIR}/${i}_${START_TIME[${j}]}.fastq"..."
				# Gera o arquivo de log
				echo "${START_TIME[${j}]} `echo $(cat ${FILTERBYSTARTTIMEDIR}/${i}_${START_TIME[${j}]}.fastq|wc -l)/4|bc`"  >> ${FILTERBYSTARTTIMEDIR}/${i}_filter.log
				# echo "${START_TIME[${j}]} $(grep ${RUNNAME} ${FILTERBYSTARTTIMEDIR}/${i}_${START_TIME[${j}]}.fastq | wc -l)" >> ${FILTERBYSTARTTIMEDIR}/${i}_filter.log
			done
		done
	else
		echo "Usando dados FILTERBYSTARTTIME analisados previamente..."
	fi
	IODIR=$FILTERBYSTARTTIMEDIR
}

function sequencing_summary2 () {
	# pycoQC summary
	# Comando para pycoQC version 2.5
	if [ ! -f "${RESULTSDIR}/basecalling_wf${WF}_pycoqc.html" ]; then
		echo -e "Executando pycoQC no sequencing summary utilizando os parâmetros QSCORE=${QSCORE} os LENGTH=${LENGTH}...\n"
		pycoQC -q -f "${BASECALLDIR}/sequencing_summary.txt" -o "${RESULTSDIR}/basecalling_wf${WF}_pycoqc.html" --report_title ${RESULTSDIR} --min_pass_qual ${QSCORE} --min_pass_len ${LENGTH}
	fi
	if [ ! -f "${RESULTSDIR}/barcoding_wf${WF}_pycoqc.html" ]; then
		echo -e "Executando pycoQC no sequencing e barcoder summaries utilizando os parâmetros QSCORE=${QSCORE} os LENGTH=${LENGTH}...\n"
		pycoQC -q -f "${BASECALLDIR}/sequencing_summary.txt" -b "${DEMUXDIR}/barcoding_summary.txt" -o "${RESULTSDIR}/barcoding_wf${WF}_pycoqc.html" --report_title ${RESULTSDIR} --min_pass_qual ${QSCORE} --min_pass_len ${LENGTH}
	fi
}

function qc_filter1 () {
	# Filtro por tamanho
	if [ ! -d $NANOFILTDIR ]; then
		mkdir $NANOFILTDIR
		# [ ! -d ${NANOFILTDIR} ] && mkdir -vp ${NANOFILTDIR}
		echo -e "executando NanoFilt em ${IODIR}...\n"
		source activate nanofilt
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			NanoFilt -l ${LENGTH} < "${IODIR}/${i}.fastq" > "${NANOFILTDIR}/${i}.fastq" 
			# Gera o arquivo de log
			echo "${i} `echo $(cat ${NANOFILTDIR}/${i}.fastq|wc -l)/4|bc`"  >> ${NANOFILTDIR}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${NANOFILTDIR}/${i}.fastq)" >> ${NANOFILTDIR}/passed_reads.log
		done
		conda deactivate
	else
		echo "Usando dados NANOFILT analisados previamente..."
	fi
	IODIR=$NANOFILTDIR
}

function qc_filter2 () {
	# Filtro de complexidade
	if [ ! -d $PRINSEQDIR ]; then
		mkdir $PRINSEQDIR
		# Link: https://chipster.csc.fi/manual/prinseq-complexity-filter.html
		echo -e "executando prinseq-lite.pl...\n"
		source activate prinseq
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			echo -e "\nResultados ${i}..."
			# Em geral, os resultados do Prinseq são salvos com a extensão. good.fastq. Nós mantivemos apenas .fastq por conveniência do pipeline
			prinseq-lite.pl -fastq "${IODIR}/${i}.fastq" -out_good "${PRINSEQDIR}/${i}" -graph_data "${PRINSEQDIR}/${i}.gd" -no_qual_header -lc_method dust -lc_threshold 40
			# Gera o arquivo de log
			echo "${i} `echo $(cat ${PRINSEQDIR}/${i}.fastq|wc -l)/4|bc`"  >> ${PRINSEQDIR}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${PRINSEQDIR}/${i}.fastq)" >> ${PRINSEQDIR}/passed_reads.log
		done
		conda deactivate
	else
		echo "Usando dados PRINSEQ analisados previamente..."
	fi
  IODIR=$PRINSEQDIR
}

function human_filter1 () {
	# Remoção das reads do genoma humano
	if [ ! -d $HUMANFILTERDIR1 ]; then
		mkdir $HUMANFILTERDIR1
		# [ ! -d "${HUMANFILTERDIR1}" ] && mkdir -vp ${HUMANFILTERDIR1}
		echo -e "Executando minimap2 & samtools para filtrar as reads do genoma humano...\n"
		source activate minimap2
		# Loop para analisar todos barcodes, um de cada vez
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			echo -e "\nCarregando os dados ${i}..."
				# Alinha as reads contra o arquivo indice do genoma humano e ordena os segmentos
				minimap2 -ax map-ont -t ${THREADS} ${HUMANREFMMI} ${IODIR}/${i}.fastq | samtools sort -@ ${THREADS} -o ${HUMANFILTERDIR1}/${i}_sorted_bam -
				# Indexa o arquivo para acesso mais rápido
				samtools index -@ ${THREADS} ${HUMANFILTERDIR1}/${i}_sorted_bam
				# Filtra as reads não mapeados Flag 4 (-f 4) para um novo arquivo filtered.sam 
				samtools view -bS -f 4 ${HUMANFILTERDIR1}/${i}_sorted_bam > ${HUMANFILTERDIR1}/${i}_bam -@ ${THREADS}
			# Salva os dados no formato .fastq
			samtools fastq ${HUMANFILTERDIR1}/${i}_bam > ${HUMANFILTERDIR1}/${i}.fastq -@ ${THREADS}
			# Gera o arquivo de log
			echo "${i} `echo $(cat ${HUMANFILTERDIR1}/${i}.fastq|wc -l)/4|bc`"  >> ${HUMANFILTERDIR1}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${HUMANFILTERDIR1}/${i}.fastq)" >> ${HUMANFILTERDIR1}/passed_reads.log
		done
		conda deactivate
	else
		echo "Usando dados HUMANFILTER analisados previamente..."
	fi
	IODIR=$HUMANFILTERDIR1
}

# Necessita ser testado
function human_filter2 () {
	# Remoção das reads do genoma humano
	if [ ! -d $HUMANFILTERDIR2 ]; then
		mkdir $HUMANFILTERDIR2
		# [ ! -d "${HUMANFILTERDIR2}" ] && mkdir -vp ${HUMANFILTERDIR2}
		echo -e "Executando gmap para filtrar as reads do genoma humano...\n"
		# Loop para analisar todos barcodes, um de cada vez
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			echo -e "\nCarregando os dados ${i}..."
			# Filtra as reads não mapeados
			# Source code: http://research-pub.gene.com/gmap
			gmapl -d GRCh38 "${IODIR}/${i}.fastq"
			# Gera o arquivo de log
			echo "${i} `echo $(cat ${HUMANFILTERDIR2}/${i}.fastq|wc -l)/4|bc`"  >> ${HUMANFILTERDIR2}/passed_reads.log
			# echo "${i} $(grep -c "runid" ${HUMANFILTERDIR2}/${i}.fastq)" >> ${HUMANFILTERDIR2}/passed_reads.log
		done
	else
		echo "Usando dados HUMANFILTER2 analisados previamente..."
	fi
	IODIR=$HUMANFILTERDIR2
}

function reads_polishing () {
	# Autocorreção das reads
	if [ ! -d $READSLEVELDIR ]; then
		mkdir $READSLEVELDIR
		# [ ! -d "${READSLEVELDIR}" ] && mkdir -vp ${READSLEVELDIR}
		echo -e "\nExecutando minimap2 & racon para autocorreção das reads contra a sequencia consenso..."
		source activate minimap2
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			echo -e "\nCarregando os dados ${i} para autocorreção...\n"
			# Alinhar todas as reads com elas mesmas para produzir sequencias consenso a partir do overlap de reads
			minimap2 -ax ava-ont -t ${THREADS} ${IODIR}/${i}.fastq ${IODIR}/${i}.fastq > ${READSLEVELDIR}/${i}_overlap.sam
			# Correção de erros a partir das sequencias consenso
			racon -t ${THREADS} -f -u ${IODIR}/${i}.fastq ${READSLEVELDIR}/${i}_overlap.sam ${IODIR}/${i}.fastq > ${READSLEVELDIR}/${i}.fasta
			# Gera o arquivo de log
			echo "${i} $(grep -c ">" ${READSLEVELDIR}/${i}.fasta)" >> ${READSLEVELDIR}/passed_reads.log
		done
		conda deactivate
	else
		echo "Usando dados READSLEVEL analisados previamente..."
	fi
  IODIR=$READSLEVELDIR
}

function kraken_reads () {
	# Classificação taxonômica das reads utilizando Kraken2
	if [ ! -d $KRAKENREADSDIR ]; then
		mkdir $KRAKENREADSDIR
		# [ ! -d "${KRAKENREADSDIR}" ] && mkdir -vp ${KRAKENREADSDIR}
		echo -e "Classificando as reads pelo Kraken2...\n"
		for i in $(find ${IODIR}/*.fasta -type f -exec basename {} .fasta \; | sort); do
			# Gera o arquivo de loglog
			echo -e "\nCarregando os dados ${i}..."
			kraken2 --db ${KRAKENDBDIR} --quick --threads ${THREADS} --report ${KRAKENREADSDIR}/${i}_report.txt --output ${KRAKENREADSDIR}/${i}_output.txt ${IODIR}/${i}.fasta
			echo -e "\nGerando o ${i}_quick_report.txt"
			~/scripts/kraken2_quick_report.sh "${KRAKENREADSDIR}/${i}_report.txt"
		done
		echo "Resultados KRAKEN2 em nível de reads obtidos com sucesso!"
	else
		echo "Resultados KRAKEN2 em nível de reads obtidos previamente!"
	fi
}

function blastn_reads () {
	# Preparação do BLASTDB local
		# Script: makeblastdb_refseq.sh
		# Concatena todas as REFSEQs num arquivo refseq.fasta único e cria o BLASTDB
		# Extrai do arquvio refseq.fasta a lista acesso refseq.acc
		# Cria a partir do arquivo refseq.acc o arquivo refseq.map que mapeia os taxid (números que identificam as espécies taxonômica)
	# Classificação taxonômica das reads utilizando blastn
	if [ ! -d $BLASTNREADSDIR ]; then
		mkdir $BLASTNREADSDIR
		# Busca as QUERIES e salva na pasta diretório BLASTNREADSDIR
		echo -e "Classificando as reads pelo BLASTN...\n"
		for i in $(find ${IODIR}/*.fasta -type f -exec basename {} .fasta \; | sort); do
			# Busca em banco de sequencias local
			blastn -db "${BLASTDBDIR}/refseq" -query "${IODIR}/${i}.fasta" -out "${BLASTNREADSDIR}/${i}.blastn" -outfmt "6 sacc staxid" -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			# Busca em banco de sequencias remota
			# blastn -db nt -remote -query ${IODIR}/${i}.fasta -out ${BLASTNREADSDIR}/${i}.blastn -outfmt "6 qacc saccver pident sscinames length mismatch gapopen evalue bitscore"  -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			# Gera o arquivo de log
			echo "${i} $(wc -l < ${BLASTNREADSDIR}/${i}.blastn)" >> ${BLASTNREADSDIR}/passed_reads.log
			~/scripts/blastn_report.sh "${BLASTNREADSDIR}/${i}.blastn"
		done
		echo "Resultados BLASTN em nível de reads obtidos com sucesso!"
	else
		echo "Resultados BLASTN em nível de reads obtidos previamente!"
	fi
}

function coverage () {
	# Faz a análise de cobertura e montagem das reads em sequencias referências
	if [ ! -d "${COVERAGEDIR}" ]; then
		mkdir -vp ${COVERAGEDIR}
		# Mapeamento das sequencias em todos os genomas virais de referência
		source activate minimap2
		if [ ! -d "${MAPPINGDIR}" ]; then
			mkdir -vp ${MAPPINGDIR}
			for j in $(find ${REFGENDIR} -type f -name "*.mmi" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
				for i in $(find ${IODIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
				  echo "Mapeando ${IODIR}/${i}.fasta..."
				  minimap2 -t ${THREADS} -ax map-ont ${REFGENDIR}/${j}.mmi ${IODIR}/${i}.fasta | samtools sort -@ ${THREADS} -o ${MAPPINGDIR}/${i}.${j}.sorted.bam -	
				  samtools view -@ ${THREADS} -h -F 4 -b ${MAPPINGDIR}/${i}.${j}.sorted.bam > ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam
				  samtools index -@ ${THREADS} ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam
				  samtools mpileup -A -d 0 -Q 0 ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam | ivar consensus -p ${MAPPINGDIR}/${i}.${j}.consensus
				done
			done
		fi
		conda deactivate
		source activate ngs
		# Análise de cobertura propriamente dita de todos os taxon
		for j in $(find ${REFGENDIR} -type f -name "*.mmi" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
			for i in $(find ${IODIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
				echo "Analisando a cobertura ${IODIR}/${i}.fasta..."
				samtools coverage ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam > ${COVERAGEDIR}/${i}.${j}.coverage.txt
				samtools coverage -A -w 32 ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam > ${COVERAGEDIR}/${i}.${j}.histogram.txt
				samtools depth ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam > ${COVERAGEDIR}/${i}.${j}.depth.txt
				fastcov.py ${MAPPINGDIR}/${i}.${j}.sorted.mapped.bam -o ${COVERAGEDIR}/${i}.${j}.fastcov.pdf -c ${COVERAGEDIR}/${i}.${j}_fastcov.txt
			done
		done
		echo "Resultados MAPPING/COVERAGE em nível de reads obtidos com sucesso!"
		# Análise de cobertura da biblioteca por taxon
		#for j in $(find ${REFGENDIR} -type f -name "$TAXON*.mmi" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
			#echo "Determinando a cobertura da biblioteca para o taxon ${j}..."
			#fastcov.py ${ASSEMBLYDIR}/barcode*.${j}.sorted.mapped.bam -o ${COVERAGEDIR}/${RUNNAME}_${MODEL}_${j}.fastcov.pdf
			#fastcov.py -l ${ASSEMBLYDIR}/barcode*.${j}.sorted.mapped.bam -o ${COVERAGEDIR}/${RUNNAME}_${MODEL}_${j}.fastcov_logscale.pdf
		#done
		conda deactivate
	else
		echo "Resultados MAPPING/COVERAGE em nível de reads obtidos previamente!"
	fi
}

function assembly () {
	# Pipeline Spades
	if [ ! -d $CONTIGSLEVELDIR ]; then
		mkdir $CONTIGSLEVELDIR
		# [ ! -d "${CONTIGSLEVELDIR}" ] && mkdir -vp ${CONTIGSLEVELDIR}
		echo -e "Executando o pipeline Spades...\n"
		for i in $(find ${IODIR}/*.fasta -type f -exec basename {} .fasta \; | sort); do
			echo -e "\nCarregando os dados ${i} para montagem...\n"
			# Pipeline Spades 
			spades.py -s ${IODIR}/${i}.fasta -o ${CONTIGSLEVELDIR}/${i} --only-assembler
			# Gera o arquivo de log
			echo "${i} $(grep -c ">" ${CONTIGSLEVELDIR}/${i}/contigs.fasta)" >> ${CONTIGSLEVELDIR}/passed_contigs.log
		done
	else
		echo "Usando dados CONTIGSLEVEL analisados previamente..."
	fi
	IODIR=$CONTIGSLEVELDIR
}

function kraken_contigs () {
	# Classificação taxonômica das contigs utilizando Kraken2
	if [ ! -d $KRAKENCONTIGSDIR ]; then
		mkdir $KRAKENCONTIGSDIR
		echo -e "Classificando as contigs pelo Kraken2...\n"
		for i in $(find ${IODIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			[ ! -d "${IODIR}/${i}" ] && continue
			echo -e "\nCarregando os dados ${i}..."
			kraken2 --db ${KRAKENDBDIR} --quick --threads ${THREADS} --report ${KRAKENCONTIGSDIR}/${i}_report.txt --output ${KRAKENCONTIGSDIR}/${i}_output.txt ${IODIR}/${i}/contigs.fasta
			echo -e "\nGerando o ${i}_quick_report.txt"
			~/scripts/kraken2_quick_report.sh "${KRAKENCONTIGSDIR}/${i}_report.txt"
		done
		echo "Resultados KRAKEN2 em nível de contigs obtidos com sucesso!"
	else
		echo "Resultados KRAKEN2 em nível de contigs obtidos previamente!"
	fi
}

function blastn_contigs () {
	# Preparação do BLASTDB local
		# Script: makeblastdb_refseq.sh
		# Concatena todas as REFSEQs num arquivo refseq.fasta único e cria o BLASTDB
		# Extrai do arquvio refseq.fasta a lista acesso refseq.acc
		# Cria a partir do arquivo refseq.acc o arquivo refseq.map que mapeia os taxid (números que identificam as espécies taxonômica)
	# Classificação taxonômica das contigs utilizando blastn
	if [ ! -d $BLASTNCONTIGSDIR ]; then
		mkdir $BLASTNCONTIGSDIR
		# Busca as QUERIES e salva na pasta diretório BLASTNCONTIGSDIR
		echo -e "Classificando as contigs pelo BLASTN...\n"
		for i in $(find ${IODIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			echo -e "\nCarregando os dados ${i}..."
			blastn -db "${BLASTDBDIR}/refseq" -query "${IODIR}/${i}/contigs.fasta" -out "${BLASTNCONTIGSDIR}/${i}.blastn" -outfmt "6 sacc staxid" -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			# Busca remota
			# blastn -db nt -remote -query ${IODIR}/${i}.fasta -out ${BLASTDIR}/${i}.blastn -outfmt "6 qacc saccver pident sscinames length mismatch gapopen evalue bitscore"  -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			# Gera o arquivo de log
			echo "${i} $(wc -l < ${BLASTNCONTIGSDIR}/${i}.blastn)" >> ${BLASTNCONTIGSDIR}/passed_reads.log
			~/scripts/blastn_report.sh "${BLASTNCONTIGSDIR}/${i}.blastn"
		done
		echo "Resultados BLASTN em nível de contigs obtidos com sucesso!"
	else
		echo "Resultados BLASTN em nível de contigs obtidos previamente!"
	fi
}

function instalacao () {
	# Instalação dos softwares requeridos
	# Cria um ambiente para cada aplicação e atualiza os pacotes, se necessário
	# Em desenvolvimento...
	echo -e "Instalando/atualizando CUTADAPT..."
	if { conda env list | grep 'cutadapt'; } >/dev/null 2>&1; then
		source activate cutadapt
		conda update --all
	else
		conda create -n cutadapt
		conda install -c bioconda cutadapt
		cutadapt --version
		conda deactivate
	fi
	echo -e "Instalando/atualizando NANOFILT..."
	if { conda env list | grep 'nanofilt'; } >/dev/null 2>&1; then
		source activate nanofilt
		conda update --all
	else
		conda create -n nanofilt
		conda install -c bioconda nanofilt
		NanoFilt --version
		conda deactivate
	fi
	echo -e "Instalando/atualizando MINIMAP2, SAMTOOLS & RACON..."
	if { conda env list | grep 'minimap2'; } >/dev/null 2>&1; then
		source activate minimap2
		conda update --all
	else
		conda create -n minimap2
		conda install -c bioconda minimap2 samtools racon
		minimap2 --version
		samtools --version
		racon --version
		conda deactivate
	fi
}

#
# Main do script
#
# Define as etapas de cada workflow
# Etapas obrigatórios: basecalling, demux/primer_removal ou demux_headcrop, reads_polishing e algum método de classificação taxonômica
declare -A workflowList=(
	[1]="setup_env sequencing_summary1 basecalling"
	[2]="setup_env sequencing_summary1 basecalling demux sequencing_summary2 primer_removal qc_filter1 qc_filter2 reads_polishing blastn_reads assembly blastn_contigs"
	[3]="setup_env sequencing_summary1 basecalling demux_headcrop sequencing_summary2 qc_filter1 qc_filter2 human_filter1 reads_polishing kraken_reads coverage assembly kraken_contigs"
	[3_filter]="setup_env sequencing_summary1 basecalling demux_headcrop filter_by_start_time sequencing_summary2 qc_filter1 qc_filter2 human_filter1 reads_polishing kraken_reads assembly kraken_contigs"
	[instalacao]="instalacao"
	)
	
# Validação do WF
keys="${!workflowList[@]}"
if [[ "${keys}" =~ "${WF}" ]]; then
	workflowSteps="${workflowList[${WF}]}"
else
	echo "Workflow ${WF} não definido!"
	exit 3
fi

# Índice para o array workflowList 0..n
#indice=$(expr $WF - 1)

# Execução das análises propriamente ditas a partir do workflow selecionado
echo "Executando o workflow $WF..."
echo "Passos do workflow $WF: ${workflowSteps[@]}"
# Separa cada etapa do workflow no vetor steps
read -r -a steps <<< "${workflowSteps[@]}"
for call_func in ${steps[@]}; do
	echo -e "\nExecutando o passo $call_func... "
	eval $call_func
	
done
exit 4
