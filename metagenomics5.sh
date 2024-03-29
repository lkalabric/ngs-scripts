#!/bin/bash

# script: metagenomics5.sh
# autores: Laise de Moraes <laisepaixao@live.com> & Luciano Kalabric <luciano.kalabric@fiocruz.br>
# instituição: Oswaldo Cruz Foundation, Gonçalo Moniz Institute, Bahia, Brazil
# criação: 09 JUN 2022
# última atualização: 11 OUT 2022
# versão 5: modulariza e personaliza as workflows a partir do uso de funções

# Descrição de cada função disponível para construção dos workflows
# sequencing_summary1
# sequencing_summary2
# basecalling
# demux
# demux_headcrop
# primer_removal
# qc_filter1
# qc_filter2
# human_filter
# reads_polishing (reads_level)
	# coverage
	# blastn_local
		# blast_report
	# kraken_local
		# kraken2_quick_report
# contifs_leves
	# blastncontig_local
		# blastn_report
	# krakencontif_local
		# kraken2_quick_report

# Validação da entrada de dados na linha de comando
RUNNAME=$1 	# Nome do dado passado na linha de comando
MODEL=$2	# Modelo de basecalling fast hac sup
WF=$3		# Workflow de bioinformatica 1, 2 ou 3
if [[ $# -eq 0 ]]; then
	echo "Falta o nome dos dados, número do worflow ou modelo Guppy Basecaller!"
	echo "Sintáxe: ./metagenomics5.sh <LIBRARY> <MODELO: fast, hac, sup> <WF: 1, 2, 3,...>"
	exit 0
fi

# Verifica se os ambientes conda ngs ou bioinfo foram criados e ativa um dos ambientes
# Tipicamente, instalamos todos os pacotes em um destes ambientes, mas, recentemente, estamos
# pensando em separa cada pacote em seu próprio ambiente por questões de compatibilidade
# com o Python!
if { conda env list | grep 'ngs'; } >/dev/null 2>&1; then
	source activate ngs
else
	if { conda env list | grep 'bioinfo'; } >/dev/null 2>&1; then
		source activate bioinfo
	else
		echo "Ambiente conda indisponível!"
		exit 0
	fi
fi

# Caminho de INPUT dos dados fast5
RAWDIR="${HOME}/data/${RUNNAME}"
if [ ! -d $RAWDIR ]; then
	echo "Pasta de dados não encontrada!"
	exit 0
fi

# Caminho de INPUT dos bancos de dados
HUMANREFDIR="${HOME}/data/GRCh38"
REFSEQDIR="${HOME}/data/REFSEQ"
BLASTDBDIR="${HOME}/data/BLAST_DB"
KRAKENDBDIR="${HOME}/data/KRAKEN2_DB" # Substituir pelo nosso banco de dados se necessário KRAKEN2_USER_DB

# Caminhos de OUTPUT das análises
echo "Preparando pastas para (re-)análise dos dados..."
RESULTSDIR="${HOME}/ngs-analysis/${RUNNAME}_${MODEL}/wf${WF}"
	# Cria a pasta de resultados
	#[[ ! -d "${RESULTSDIR}" ]] || mkdir -vp ${RESULTSDIR}
	read -p "Re-analisar os dados [S-apagar e re-analisa os dados / N-continuar as análises de onde pararam]? " -n 1 -r
	if [[ $REPLY =~ ^[Ss]$ ]]; then
		# Reseta a pasta de resultados do worflow
		echo "Apagando as pastas e re-iniciando as análises..."
		[[ ! -d "${RESULTSDIR}" ]] || mkdir -vp ${RESULTSDIR} && rm -r "${RESULTSDIR}"; mkdir -vp "${RESULTSDIR}"
	fi
BASECALLDIR="${RESULTSDIR}/BASECALL"
DEMUXDIR="${RESULTSDIR}/DEMUX"
DEMUXCATDIR="${RESULTSDIR}/DEMUX_CAT"
QCFILTERSDIR="${RESULTSDIR}/QC_FILTERS"
CUTADAPTDIR="${RESULTSDIR}/CUTADAPT"
NANOFILTDIR="${RESULTSDIR}/NANOFILT"
PRINSEQDIR="${RESULTSDIR}/PRINSEQ"
HUMANFILTERDIR1="${RESULTSDIR}/HUMANFILTER1"
HUMANFILTERDIR2="${RESULTSDIR}/HUMANFILTER2"
READSLEVELDIR="${RESULTSDIR}/READS_LEVEL"
KRAKENREADSDIR="${READSLEVELDIR}/KRAKEN"
BLASTNREADSDIR="${READSLEVELDIR}/BLASTN"
COVERAGEDIR="${RESULTSDIR}/READS_LEVEL/COVERAGE"
CONTIGSLEVELDIR="${RESULTSDIR}/CONTIGS_LEVEL"
KRAKENCONTIGSDIR="${CONTIGSLEVELDIR}/KRAKEN"
BLASTNCONTIGSDIR="${CONTIGSLEVELDIR}/BLASTN"

# Pausa a execução para debug
# read -p "Press [Enter] key to continue..."

# Parâmetros de qualidade mínima
QSCORE=9	# Default Fast min_qscore=8; Hac min_qscore=9; Sup min_qscore=10
LENGTH=100

# Parâmetro de otimização minimap2, samtools, racon e kraken2
THREADS="$(lscpu | grep 'CPU(s):' | awk '{print $2}' | sed -n '1p')"

# Parâmetros minimap2 
# wget http://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_38/GRCh38.p13.genome.fa.gz -P ${HUMANREFDIR}
HUMANREFSEQ="${HUMANREFDIR}/GRCh38.p13.genome.fa.gz"
HUMANREFMMI="${HUMANREFDIR}/GRCh38.p13.genome.mmi"
# Cria o arquivo índice do genoma humano para reduzir o tempo de alinhamento
if [ ! -f $HUMANREFMMI ]; then
	minimap2 -d $HUMANREFMMI $HUMANREFSEQ
fi

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
		# Renomeia a pasta contendo as reads unclassified para barcode00 para análise
		# [ -d "${DEMUXDIR}/unclassified" ] && mv "${DEMUXDIR}/unclassified" "${DEMUXDIR}/barcode00"
		# Concatena todos arquivos .fastq de cada barcode em um arquivo .fastq único
		[ ! -d ${DEMUXCATDIR} ] && mkdir -vp ${DEMUXCATDIR}
		for i in $(find ${DEMUXDIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			[ -d "${DEMUXDIR}/${i}" ] && cat ${DEMUXDIR}/${i}/*.fastq > "${DEMUXCATDIR}/${i}.fastq"
			grep -c "runid" ${DEMUXCATDIR}/${i}.fastq >> ${DEMUXCATDIR}/passed_reads.log
		done
	else
		echo "Usando dados DEMUX_CAT analisados previamente..."
	fi
  IODIR=$DEMUXCATDIR  
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
		[ -d "${DEMUXDIR}/unclassified" ] && mv "${DEMUXDIR}/unclassified" "${DEMUXDIR}/barcode00"
		# Concatena todos arquivos .fastq de cada barcode em um arquivo .fastq único
		[ ! -d ${DEMUXCATDIR} ] && mkdir -vp ${DEMUXCATDIR}
		for i in $(find ${DEMUXDIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			[ -d "${DEMUXDIR}/${i}" ] && cat ${DEMUXDIR}/${i}/*.fastq > "${DEMUXCATDIR}/${i}.fastq"
			grep -c "runid" ${DEMUXCATDIR}/${i}.fastq >> ${DEMUXCATDIR}/passed_reads.log
		done
	else
		echo "Usando dados DEMUX_CAT analisados previamente..."
	fi
  IODIR=$DEMUXCATDIR
}

function sequencing_summary2 () {
	# pycoQC summary
	# Comando para pycoQC version 2.5
	if [ ! -f "${RESULTSDIR}/basecalling_wf${WF}_pycoqc.html" ]; then
		echo -e "Executando pycoQC no sequencing summary com o parâmetro default QSCORE=9...\n"
		pycoQC -q -f "${BASECALLDIR}/sequencing_summary.txt" -o "${RESULTSDIR}/basecalling_wf${WF}_pycoqc.html" --report_title ${RESULTSDIR} --min_pass_qual ${QSCORE} --min_pass_len ${LENGTH}
	fi
	if [ ! -f "${RESULTSDIR}/barcoding_wf${WF}_pycoqc.html" ]; then
		echo -e "Executando pycoQC no sequencing e barecoder summaries utilizandos os LENGHT=100 e QSCORE=9...\n"
		pycoQC -q -f "${BASECALLDIR}/sequencing_summary.txt" -b "${DEMUXDIR}/barcoding_summary.txt" -o "${RESULTSDIR}/barcoding_wf${WF}_pycoqc.html" --report_title ${RESULTSDIR} --min_pass_qual ${QSCORE} --min_pass_len ${LENGTH}
	fi
}

function primer_removal () {
	# Remoção dos primers
	if [ ! -d $CUTADAPTDIR ]; then
		mkdir -vp ${CUTADAPTDIR}
		# [ ! -d ${CUTADAPTDIR} ] && mkdir -vp ${CUTADAPTDIR}	
		PRIMER="GTTTCCCACTGGAGGATA"
		echo -e "executando cutadapt em ${IODIR}...\n"
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			cutadapt -g ${PRIMER} -e 0.2 --discard-untrimmed -o "${CUTADAPTDIR}/${i}.fastq" "${DEMUXCATDIR}/${i}.fastq"
			# echo -e "\nResultados ${i} $(grep -c "runid" ${CUTADAPTDIR}/${i}.fastq | cut -d : -f 2 | awk '{s+=$1} END {printf "%.0f\n",s}')"
			grep -c "runid" ${CUTADAPTDIR}/${i}.fastq >> ${CUTADAPTDIR}/passed_reads.log
		done
	else
		echo "Usando dados CUTADAPT analisados previamente..."
	fi
  IODIR=$CUTADAPTDIR
}

function qc_filter1 () {
	# Filtro por tamanho
	if [ ! -d $NANOFILTDIR ]; then
		mkdir $NANOFILTDIR
		# [ ! -d ${NANOFILTDIR} ] && mkdir -vp ${NANOFILTDIR}
		echo -e "executando NanoFilt em ${IODIR}...\n"
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			NanoFilt -l ${LENGTH} < "${IODIR}/${i}.fastq" > "${NANOFILTDIR}/${i}.fastq" 
			grep -c "runid" ${NANOFILTDIR}/${i}.fastq >> ${NANOFILTDIR}/passed_reads.log
		done
	else
		echo "Usando dados NANOFILT analisados previamente..."
	fi
	IODIR=$NANOFILTDIR
}

function qc_filter2 () {
	# Filtro de complexidade
	if [ ! -d $PRINSEQDIR ]; then
		mkdir $PRINSEQDIR
		# [ ! -d ${PRINSEQDIR} ] && mkdir -vp ${PRINSEQDIR}
		# Link: https://chipster.csc.fi/manual/prinseq-complexity-filter.html
		echo -e "executando prinseq-lite.pl...\n"
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			echo -e "\nResultados ${i}..."
			# Em geral, os resultados do Prinseq são salvos com a extensão. good.fastq. Nós mantivemos apenas .fastq por conveniência do pipeline
			prinseq-lite.pl -fastq "${IODIR}/${i}.fastq" -out_good "${PRINSEQDIR}/${i}" -graph_data "${PRINSEQDIR}/${i}.gd" -no_qual_header -lc_method dust -lc_threshold 40
			grep -c "runid" ${PRINSEQDIR}/${i}.fastq >> ${PRINSEQDIR}/passed_reads.log
		done
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
			grep -c "runid" ${HUMANFILTERDIR1}/${i}.fastq >> ${HUMANFILTERDIR1}/passed_reads.log
		done
	else
		echo "Usando dados HUMANFILTER analisados previamente..."
	fi
	IODIR=$HUMANFILTERDIR1
}

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
			gmapl -d GRCh38 "${IODIR}/${i}.fastq"
			grep -c "runid" ${HUMANFILTERDIR2}/${i}.fastq >> ${HUMANFILTERDIR2}/passed_reads.log
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
		for i in $(find "${IODIR}"/*.fastq -type f -exec basename {} .fastq \; | sort); do
			echo -e "\nCarregando os dados ${i} para autocorreção...\n"
			# Alinhar todas as reads com elas mesmas para produzir sequencias consenso a partir do overlap de reads
			minimap2 -ax ava-ont -t ${THREADS} ${IODIR}/${i}.fastq ${IODIR}/${i}.fastq > ${READSLEVELDIR}/${i}_overlap.sam
			# Correção de erros a partir das sequencias consenso
			racon -t ${THREADS} -f -u ${IODIR}/${i}.fastq ${READSLEVELDIR}/${i}_overlap.sam ${IODIR}/${i}.fastq > ${READSLEVELDIR}/${i}.fasta
			grep -c ">" ${READSLEVELDIR}/${i}.fasta >> ${READSLEVELDIR}/passed_reads.log
		done
	else
		echo "Usando dados READSLEVEL analisados previamente..."
	fi
  IODIR=$READSLEVELDIR
}

function coverage () {
	# Faz a análise de cobertura e montagem das reads em sequencias referências
	[ ! -d "${COVERAGEDIR}" ] && mkdir -vp ${COVERAGEDIR}
}

function kraken_local () {
	# Classificação taxonômica utilizando Kraken2
	if [ ! -d $KRAKENREADSDIR ]; then
		mkdir $KRAKENREADSDIR
		# [ ! -d "${KRAKENREADSDIR}" ] && mkdir -vp ${KRAKENREADSDIR}
		echo -e "Classificação das reads pelo Kraken2...\n"
		for i in $(find ${IODIR}/*.fasta -type f -exec basename {} .fasta \; | sort); do
			echo -e "\nCarregando os dados ${i}..."
			# kraken2 --db ${KRAKENDBDIR} --threads ${THREADS} --report ${IODIR}/${i}_report.txt --report-minimizer-data --output ${IODIR}/${i}_output.txt ${IODIR}/${i}.filtered.fasta
			kraken2 --db ${KRAKENDBDIR} --quick --threads ${THREADS} --report ${KRAKENREADSDIR}/${i}_report.txt --output ${KRAKENREADSDIR}/${i}_output.txt ${IODIR}/${i}.fasta
			echo -e "\nGerando o ${i}_report.txt"
			~/scripts/kraken2_quick_report.sh "${KRAKENREADSDIR}/${i}_quick_report.txt"
		done
	else
		echo "Relatórios KRAKEN2 já emitidos..."
	fi
}

function blastn_local () {
	# Classificação taxonômica utilizando blastn
	# Preparação do BLASTDB local
	# Script: makeblastdb_refseq.sh
		# Concatena todas as REFSEQs num arquivo refseq.fasta único e cria o BLASTDB
		# Extrai do arquvio refseq.fasta a lista acesso refseq.acc
		# Cria a partir do arquivo refseq.acc o arquivo refseq.map que mapeia os taxid (números que identificam as espécies taxonômica)

	# Busca as QUERIES no BLASTDB local e salva na pasta BLASTNREADSDIR
	if [ ! -d $BLASTNREADSDIR ]; then
		mkdir $BLASTNREADSDIR
		# [ ! -d ${BLASTNREADSDIR} ] && mkdir -vp ${BLASTNREADSDIR}
		echo -e "Classificação das reads pelo BLASTN...\n"
		for i in $(find ${IODIR}/*.fasta -type f -exec basename {} .fasta \; | sort); do
			blastn -db "${BLASTDBDIR}/refseq" -query "${IODIR}/${i}.fasta" -out "${BLASTNREADSDIR}/${i}.blastn" -outfmt "6 sacc staxid" -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			# Busca remota
			# blastn -db nt -remote -query ${IODIR}/${i}.fasta -out ${BLASTNREADSDIR}/${i}.blastn -outfmt "6 qacc saccver pident sscinames length mismatch gapopen evalue bitscore"  -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			wc -l < ${BLASTNREADSDIR}/${i}.blastn >> ${BLASTNREADSDIR}/passed_reads.log
			~/scripts/blastn_report.sh "${BLASTNREADSDIR}/${i}.blastn"
		done
	else
		echo "Relatórios BLASTN já emitidos..."
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
			spades -s ${IODIR}/${i}.fasta -o ${CONTIGSLEVELDIR}/${i} --only-assembler
			grep -c ">" ${CONTIGSLEVELDIR}/${i}/contigs.fasta >> ${CONTIGSLEVELDIR}/passed_contigs.log
		done
	else
		echo "Usando dados CONTIGSLEVEL analisados previamente..."
	fi
	IODIR=$CONTIGSLEVELDIR
}

function krakencontig_local () {
	# Classificação taxonômica utilizando Kraken2
	if [ ! -d $KRAKENCONTIGSDIR ]; then
		mkdir $KRAKENCONTIGSDIR
		echo -e "Classificação das contigs pelo Kraken2...\n"
		for i in $(find ${IODIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			[ ! -d "${IODIR}/${i}" ] && continue
			echo -e "\nCarregando os dados ${i}..."
			kraken2 --db ${KRAKENDBDIR} --quick --threads ${THREADS} --report ${KRAKENCONTIGSDIR}/${i}_report.txt --output ${KRAKENCONTIGSDIR}/${i}_output.txt ${IODIR}/${i}/contigs.fasta
			echo -e "\nGerando o ${i}_report.txt"
			~/scripts/kraken2_quick_report.sh "${KRAKENCONTIGSDIR}/${i}_quick_report.txt"
		done
	else
		echo "Relatórios Kraken2 já emitidos..."
	fi
}

function blastncontig_local () {
	# Classificação taxonômica utilizando blastn
	# Preparação do BLASTDB local
	# Script: makeblastdb_refseq.sh
		# Concatena todas as REFSEQs num arquivo refseq.fasta único e cria o BLASTDB
		# Extrai do arquvio refseq.fasta a lista acesso refseq.acc
		# Cria a partir do arquivo refseq.acc o arquivo refseq.map que mapeia os taxid (números que identificam as espécies taxonômica)
	if [ ! -d $BLASTNCONTIGSDIR ]; then
		mkdir $BLASTNCONTIGSDIR
		# [ ! -d ${BLASTDIR} ] && mkdir -vp ${BLASTDIR}
		# Busca as QUERIES no BLASTDB local e salva na pasta BLASTDIR
		# [ -z "$IODIR" ] && IODIR=$READSLEVELDIR
		echo -e "Classificação das contigs pelo BLASTN...\n"
		for i in $(find ${IODIR} -mindepth 1 -type d -name "barcode*" -exec basename {} \; | sort); do
			echo -e "\nCarregando os dados ${i}..."
			blastn -db "${BLASTDBDIR}/refseq" -query "${IODIR}/${i}/contigs.fasta" -out "${BLASTNCONTIGSDIR}/${i}.blastn" -outfmt "6 sacc staxid" -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			# Busca remota
			# blastn -db nt -remote -query ${IODIR}/${i}.fasta -out ${BLASTDIR}/${i}.blastn -outfmt "6 qacc saccver pident sscinames length mismatch gapopen evalue bitscore"  -evalue 0.000001 -qcov_hsp_perc 90 -max_target_seqs 1
			wc -l < ${BLASTNCONTIGSDIR}/${i}.blastn >> ${BLASTNCONTIGSDIR}/passed_reads.log
			~/scripts/blastn_report.sh "${BLASTNCONTIGSDIR}/${i}.blastn"
		done
	else
		echo "Relatórios BLASTN já emitidos..."
	fi
}

#
# Main do script
#

# Define as etapas de cada workflow
# Etapas obrigatórios: basecalling, demux/primer_removal ou demux_headcrop, reads_polishing e algum método de classificação taxonômica
workflowList=(
	'sequencing_summary1 basecalling'
	'sequencing_summary1 basecalling demux sequencing_summary2 primer_removal qc_filter1 qc_filter2 reads_polishing blastn_local assembly blastncontig_local'
	'sequencing_summary1 basecalling demux_headcrop sequencing_summary2 qc_filter1 qc_filter2 human_filter1 reads_polishing kraken_local assembly krakencontig_local'
  	'sequencing_summary1 basecalling demux sequencing_summary2 primer_removal qc_filter1 qc_filter2 reads_polishing kraken_local assembly krakencontig_local'
	'sequencing_summary1 basecalling demux sequencing_summary2 primer_removal human_filter1 qc_filter1 qc_filter2 reads_polishing blastn_local assembly blastncontig_local'
	'sequencing_summary1 basecalling demux_headcrop sequencing_summary2 human_filter1 qc_filter1 qc_filter2 reads_polishing kraken_local assembly krakencontig_local'
)

# Validação do WF
if [[ $WF -gt ${#workflowList[@]} ]]; then
	echo "Workflow não definido!"
	exit 3
fi
# Índice para o array workflowList 0..n
indice=$(expr $WF - 1)

# Execução das análises propriamente ditas a partir do workflow selecionado
echo "Executando o workflow WF$WF..."
echo "Passos do WF$WF: ${workflowList[$indice]}"
# Separa cada etapa do workflow no vetor steps
read -r -a steps <<< "${workflowList[$indice]}"
for call_func in ${steps[@]}; do
	echo -e "\nExecutando o passo $call_func... "
	eval $call_func
	
done
exit 4

# Análise de cobertura do sequenciamento
# Genomas referência e plot de cobertura
CHIKVREFSEQ="${REFSEQ}/Togaviridae/NC_004162.2_CHIKV-S27.fasta"
DENV1REFSEQ="${REFSEQ}/Flaviviridae/NC_001477.1_DENV1.fasta"
DENV2REFSEQ="${REFSEQ}/Flaviviridae/NC_001474.2_DENV2.fasta"
DENV3REFSEQ="${REFSEQ}/Flaviviridae/NC_001475.2_DENV3.fasta"
DENV4REFSEQ="${REFSEQ}/Flaviviridae/NC_002640.1_DENV4.fasta"
ZIKVREFSEQ="${REFSEQ}/Flaviviridae/NC_012532.1_ZIKV.fasta"
HIV1REFSEQ="${REFSEQ}/Retroviridae/NC_001802.1_HIV1.fasta"

# Mapeamento CHIKV
#for i in $(find ${READSLEVELDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	minimap2 -t ${THREADS} -ax map-ont ${CHIKVREFSEQ} ${READSLEVELDIR}/${i}.corrected.fasta | samtools sort -@ ${THREADS} -o ${ASSEMBLYDIR}/${i}.chikv.sorted.bam -
#	samtools view -@ ${THREADS} -h -F 4 -b ${ASSEMBLYDIR}/${i}.chikv.sorted.bam > ${ASSEMBLYDIR}/${i}.chikv.sorted.mapped.bam
#	samtools index -@ ${THREADS} ${ASSEMBLYDIR}/${i}.chikv.sorted.mapped.bam
#	samtools mpileup -A -B -Q 0 --reference ${CHIKVREFSEQ} ${ASSEMBLYDIR}/${i}.chikv.sorted.mapped.bam | ivar consensus -p ${ASSEMBLYDIR}/${i}.chikv -n N -i ${i}
#done

# Mapeamento DENV1
#for i in $(find ${READSLEVELDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	minimap2 -t ${THREADS} -ax map-ont ${DENV1REFSEQ} ${READSLEVELDIR}/${i}.corrected.fasta | samtools sort -@ ${THREADS} -o ${ASSEMBLYDIR}/${i}.denv1.sorted.bam -
#	samtools view -@ ${THREADS} -h -F 4 -b ${ASSEMBLYDIR}/${i}.denv1.sorted.bam > ${ASSEMBLYDIR}/${i}.denv1.sorted.mapped.bam
#	samtools index -@ ${THREADS} ${ASSEMBLYDIR}/${i}.denv1.sorted.mapped.bam
#	samtools mpileup -A -B -Q 0 --reference ${DENV1REFSEQ} ${ASSEMBLYDIR}/${i}.denv1.sorted.mapped.bam | ivar consensus -p ${ASSEMBLYDIR}/${i}.denv1 -n N -i ${i}
#done

# Mapeamento DENV2
#for i in $(find ${READSLEVELDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	minimap2 -t ${THREADS} -ax map-ont ${DENV2REFSEQ} ${READSLEVELDIR}/${i}.corrected.fasta | samtools sort -@ ${THREADS} -o ${ASSEMBLYDIR}/${i}.denv2.sorted.bam -
#	samtools view -@ ${THREADS} -h -F 4 -b ${ASSEMBLYDIR}/${i}.denv2.sorted.bam > ${ASSEMBLYDIR}/${i}.denv2.sorted.mapped.bam
#	samtools index -@ ${THREADS} ${ASSEMBLYDIR}/${i}.denv2.sorted.mapped.bam
#	samtools mpileup -A -B -Q 0 --reference ${DENV2REFSEQ} ${ASSEMBLYDIR}/${i}.denv2.sorted.mapped.bam | ivar consensus -p ${ASSEMBLYDIR}/${i}.denv2 -n N -i ${i}
#done

# Mapeamento DENV3
#for i in $(find ${READSLEVELDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	minimap2 -t ${THREADS} -ax map-ont ${DENV3REFSEQ} ${READSLEVELDIR}/${i}.corrected.fasta | samtools sort -@ ${THREADS} -o ${ASSEMBLYDIR}/${i}.denv3.sorted.bam -
#	samtools view -@ ${THREADS} -h -F 4 -b ${ASSEMBLYDIR}/${i}.denv3.sorted.bam > ${ASSEMBLYDIR}/${i}.denv3.sorted.mapped.bam
#	samtools index -@ ${THREADS} ${ASSEMBLYDIR}/${i}.denv3.sorted.mapped.bam
#	samtools mpileup -A -B -Q 0 --reference ${DENV3REFSEQ} ${ASSEMBLYDIR}/${i}.denv3.sorted.mapped.bam | ivar consensus -p ${ASSEMBLYDIR}/${i}.denv3 -n N -i ${i}
#done

# Mapeamento DENV4
#for i in $(find ${READSLEVELDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	minimap2 -t ${THREADS} -ax map-ont ${DENV4REFSEQ} ${READSLEVELDIR}/${i}.corrected.fasta | samtools sort -@ ${THREADS} -o ${ASSEMBLYDIR}/${i}.denv4.sorted.bam -
#	samtools view -@ ${THREADS} -h -F 4 -b ${ASSEMBLYDIR}/${i}.denv4.sorted.bam > ${ASSEMBLYDIR}/${i}.denv4.sorted.mapped.bam
#	samtools index -@ ${THREADS} ${ASSEMBLYDIR}/${i}.denv4.sorted.mapped.bam
#	samtools mpileup -A -B -Q 0 --reference ${DENV4REFSEQ} ${ASSEMBLYDIR}/${i}.denv4.sorted.mapped.bam | ivar consensus -p ${ASSEMBLYDIR}/${i}.denv4 -n N -i ${i}
#done

# Mapeamento ZIKV
#for i in $(find ${READSLEVELDIR} -type f -name "*.fasta" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	minimap2 -t ${THREADS} -ax map-ont ${ZIKVREFSEQ} ${READSLEVELDIR}/${i}.corrected.fasta | samtools sort -@ ${THREADS} -o ${ASSEMBLYDIR}/${i}.zikv.sorted.bam -
#	samtools view -@ ${THREADS} -h -F 4 -b ${ASSEMBLYDIR}/${i}.zikv.sorted.bam > ${ASSEMBLYDIR}/${i}.zikv.sorted.mapped.bam
#	samtools index -@ ${THREADS} ${ASSEMBLYDIR}/${i}.zikv.sorted.mapped.bam
#	samtools mpileup -A -B -Q 0 --reference ${ZIKVREFSEQ} ${ASSEMBLYDIR}/${i}.zikv.sorted.mapped.bam | ivar consensus -p ${ASSEMBLYDIR}/${i}.zikv -n N -i ${i}
#done

#source activate plot
#for i in $(find ${ASSEMBLYDIR} -type f -name "*.sorted.mapped.bam" | while read o; do basename $o | cut -d. -f1; done | sort | uniq); do
#	fastcov ${ASSEMBLYDIR}/barcode*.chikv.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_chikv.pdf
#	fastcov -l ${ASSEMBLYDIR}/barcode*.chikv.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_chikv_log.pdf
#	fastcov ${ASSEMBLYDIR}/barcode*.denv1.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv1.pdf
#	fastcov -l ${ASSEMBLYDIR}/barcode*.denv1.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv1_log.pdf
#	fastcov ${ASSEMBLYDIR}/barcode*.denv2.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv2.pdf
#	fastcov -l ${ASSEMBLYDIR}/barcode*.denv2.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv2_log.pdf
#	fastcov ${ASSEMBLYDIR}/barcode*.denv3.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv3.pdf
#	fastcov -l ${ASSEMBLYDIR}/barcode*.denv3.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv3_log.pdf
#	fastcov ${ASSEMBLYDIR}/barcode*.denv4.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv4.pdf
#	fastcov -l ${ASSEMBLYDIR}/barcode*.denv4.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_denv4_log.pdf
#	fastcov ${ASSEMBLYDIR}/barcode*.zikv.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_zikv.pdf
#	fastcov -l ${ASSEMBLYDIR}/barcode*.zikv.sorted.mapped.bam -o ${ASSEMBLYDIR}/assembly_zikv_log.pdf
#done

#
# Contig-level taxid
#
