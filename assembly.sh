#!/bin/bash

# script: assembly.sh
# autor: Luciano Kalabric <luciano.kalabric@fiocruz.br>
# instituição: Oswaldo Cruz Foundation, Gonçalo Moniz Institute, Bahia, Brazil
# objetivo: testar diferentes montadores
# criação: 25 AGO 2021
# ultima atualização: 26 JAN 2022
# atualização: configuração de variáveis e teste do método 6

# Validação da entrada de dados na linha de comando
RUNNAME=$1 	# Nome do dado passado na linha de comando
MODEL=$2	# Modelo de basecalling fast hac sup
WF=31		# Workflow de bioinformatica 1, 2 ou 31
BARCODE=$3	# Barcode
MONTADOR=$4	# Montador

if [[ $# -eq 0 ]]; then
	echo "Falta o nome dos dados, número do worflow ou modelo Guppy Basecaller!"
	echo "Sintáxe: assembly.sh <LIBRARY> <MODELO: fast,hac,sup> <BARCODE: barcode01,barcode02...> <MONTADOR: 1,2,3...>"
	exit 0
fi
# Caminho de INPUT dos dados fastq
NGSDIR="${HOME}/ngs-analysis/${RUNNAME}_${MODEL}/wf${WF}" # Se análise começar com o Barcoder
if [ ! -d $NGSDIR ]; then
	echo "Pasta de dados não encontrada!"
	exit 0
fi
# Dados a partir do resultado PRINSEQ
#SAMPLE="${NGSDIR}/PRINSEQ/${BARCODE}.good.fastq"

# Dados a partir do resultado RACON
SAMPLE="${NGSDIR}/READS_LEVEL/${BARCODE}.corrected.fasta"

# Caminhos de OUTPUT das análises
ASSEMBLYDIR="${NGSDIR}/ASSEMBLY"


REFSEQ="${HOME}/data/REFSEQ/Retroviridae/NC_001802.1_HIV1.fasta"
#REFSEQ="${HOME}/data/REFSEQ/Hepacivirus/M62321.1_HCV1a.fasta"
#REFSEQ="${HOME}/data/REFSEQ/Hepacivirus/D90208.1_HCV1b.fasta"
#REFSEQ="${HOME}/data/REFSEQ/Hepacivirus/D17763.1_HCV3a.fasta"
# 1 Mapea as reads usando um genoma referência
if [ $MONTADOR -eq 1 ]; then
	source activate ngs
	# long sequences against a reference genome
	minimap2 -t 12 -ax map-ont ${REFSEQ} ${SAMPLE} -o "${ASSEMBLYDIR}/1.minimap.${BARCODE}.mapped.sam"
	samtools sort "${ASSEMBLYDIR}/1.minimap.${BARCODE}.mapped.sam" -o "${ASSEMBLYDIR}/1.minimap.${BARCODE}.mapped.sorted.bam"
	fastcov.py "${ASSEMBLYDIR}/1.minimap.${BARCODE}.mapped.sorted.bam" -o "${ASSEMBLYDIR}/1.minimap.${BARCODE}.fastcov.pdf"
	exit 1
fi

# 2 De Novo assembly using minimap2-miniasm pipeline (gera unitigs sequences)
# Link: https://timkahlke.github.io/LongRead_tutorials/ASS_M.html
if [ $MONTADOR -eq 2 ]; then
	minimap2 -x ava-ont \
	 ${SAMPLE} \
	 ${SAMPLE} \
	| gzip -1 > "${ASSEMBLYDIR}/2.minimap.${BARCODE}.paf.gz"

	miniasm -f \
	 ${SAMPLE} \
	"${ASSEMBLYDIR}/2.minimap.$BARCODE.paf.gz" > "${ASSEMBLYDIR}/2.miniasm.$BARCODE.gfa"
	awk '/^S/{print ">"$2"\n"$3}' "${ASSEMBLYDIR}/2.miniasm.$BARCODE.gfa" > "${ASSEMBLYDIR}/2.miniasm.$BARCODE.fasta"
	exit 2
fi

# 3 Montagem por referência usando minimap2-samtools
# Link: https://www.biostars.org/p/472927/
if [ $MONTADOR -eq 3 ]; then
	source activate ngs
	# Cria um indice antes de mapear
	minimap2 -t 12 -ax map-ont ${REFSEQ} ${SAMPLE} -o "${ASSEMBLYDIR}/3.minimap.${BARCODE}.mapped.sam"

	# Convert sam to bam
	samtools view -S -b "${ASSEMBLYDIR}/3.minimap.${BARCODE}.mapped.sam" > "${ASSEMBLYDIR}/3.minimap.${BARCODE}.mapped.bam"

	# Sort the alignment
	samtools sort "${ASSEMBLYDIR}/3.minimap.${BARCODE}.mapped.bam" -o "${ASSEMBLYDIR}/3.minimap.${BARCODE}.mapped.sorted.bam"
	
	# Get consensus fastq file
	bcftools mpileup -f ${REFSEQ} "${ASSEMBLYDIR}/3.minimap.${BARCODE}.mapped.sorted.bam" | bcftools call -c | vcfutils.pl vcf2fq > "${ASSEMBLYDIR}/3.minimap.${BARCODE}.consensus.fastq"

	# Convert .fastq to .fasta
	seqtk seq -aQ64 -q13 -n N "${ASSEMBLYDIR}/3.minimap.${BARCODE}.consensus.fastq" > "${ASSEMBLYDIR}/3.minimap.${BARCODE}.consensus.fasta"
	exit 3
fi

# 4 Montar as reads usando minimap2-miniasm-racon pipeline
# Link: https://gist.github.com/mjoppich/18b7a07074b59bd34056df6fe7b08d05
if [ $MONTADOR -eq 4 ]; then
	source activate ngs
	# use presets (no test data) # Oxford Nanopore genomic reads
	minimap2 -t 12 -ax map-ont ../data/REFSEQ/Flaviviridae/NC_001477.1_DENV1.fasta ../ngs-analysis/DENV_FTA_1_hac/wf31/PRINSEQ/barcode01.good.fastq -o "barcode01.$1.axligned.sam"
	samtools sort "barcode01.$1.axligned.sam" -o "barcode01.$1.axligned.sorted.bam"
	exit 4
fi

# 5 Montagem da sequencia consenso usando um genoma referência
# Link: https://github.com/jts/nanopolish
if [ $MONTADOR -eq 5 ]; then
	# Pré-processamento dos dados
	nanopolish index -d ../data/DENV_FTA_1/DENV_Run1_data/fast5_pass/ -s ../data/DENV_FTA_1/DENV_Run1_data/sequencing_summary/MT-110616_20190710_214507_FAK92171_minion_sequencing_run_DENV_FTA_1_sequencing_summary.txt "${OUTDIR}/barcode01.fasta"
	# Computa uma nova sequencia consenso
	minimap2 -t 12 -ax map-ont ../data/REFSEQ/Flaviviridae/NC_001477.1_DENV1.fasta ../ngs-analysis/DENV_FTA_1_hac/wf31/PRINSEQ/barcode01.good.fastq -o "$OUTDIR/barcode01.$1.axligned.sam"
	samtools sort "$OUTDIR/barcode01.$1.axligned.sam" -o "$OUTDIR/barcode01.$1.axligned.sorted.bam"
	samtools index "$OUTDIR/barcode01.$1.axligned.sorted.bam"
	# Quebra o genoma em pedações de 50Kb e monta em paralelo
	#	python3 nanopolish_makerange.py ../data/REFSEQ/Flaviviridae/NC_001477.1_DENV1.fasta | parallel --results nanopolish.results -P 8 \
	nanopolish variants -o "${OUTDIR}/polished.vcf" -r "$OUTDIR/barcode01.fasta" -b "$OUTDIR/barcode01.$1.axligned.sorted.bam" -g ../data/REFSEQ/Flaviviridae/NC_001477.1_DENV1.fasta -t 4 --min-candidate-frequency 0.1 -p 1
#	nanopolish variants --consensus -o polished.{1}.vcf -w {1} -r ../ngs-analysis/DENV_FTA_1_hac/wf31/PRINSEQ/barcode01.good.fastq -b "barcode01.$1.axligned.sorted.bam" -g ../data/REFSEQ/Flaviviridae/NC_001477.1_DENV1.fasta -t 4 --min-candidate-frequency 0.1

#	nanopolish variantes --consensus  -d ../ngs-analysis/DENV_FTA_1_hac/wf31/PRINSEQ/barcode01.good.fastq -o "barcode01.$1.axligned.sam"
#	samtools sort "barcode01.$1.axligned.sam" -o "barcode01.$1.axligned.sorted.bam"
	exit 5
fi

# 6 Montagem da sequencia consenso usando um genoma referência
# Link: https://github.com/jts/nanopolish
if [ $MONTADOR -eq 6 ]; then
	# Indexando a sequencia referencia
	bwa index $REFSEQ
	bwa mem $REFSEQ "../ngs-analysis/$RUNNAME/wf31/PRINSEQ/$BARCODE.good.fastq" > "$OUTDIR/$BARCODE.$1.bwa-mem.sam"
	samtools sort "$OUTDIR/$BARCODE.$1.bwa-mem.sam" -o "$OUTDIR/$BARCODE.$1.bwa-mem.sorted.bam"
	samtools index "$OUTDIR/$BARCODE.$1.bwa-mem.sorted.bam"
	samtools coverage "$OUTDIR/$BARCODE.$1.bwa-mem.sorted.bam" -m -o "$OUTDIR/$BARCODE.$1.coverage"
	cat "../assembly/$BARCODE.6.coverage"
	fastcov.py "$OUTDIR/$BARCODE.$1.bwa-mem.sorted.bam" -o "../assembly/$BARCODE.6.fastcov.pdf"
	exit 6
fi

# 7 Montagem utilizando wtdbg2
# Link: https://github.com/ruanjue/wtdbg2
if [ $MONTADOR -eq 7 ]; then
	# Ativar o ambiente Conda
	source activate ngs
	
	# assemble long reads
	wtdbg2 -x ont -i $SAMPLE -t 12 -fo $HOME/assembly/dbg

	# derive consensus
	wtpoa-cns -t 16 -i $HOME/assembly/dbg.ctg.lay.gz -fo $HOME/assembly/dbg.raw.fa

	# polish consensus, not necessary if you want to polish the assemblies using other tools
	#minimap2 -t16 -ax map-pb -r2k dbg.raw.fa reads.fa.gz | samtools sort -@4 >dbg.bam
	#samtools view -F0x900 dbg.bam | ./wtpoa-cns -t 16 -d dbg.raw.fa -i - -fo dbg.cns.fa

	# Addtional polishment using short reads
	#bwa index dbg.cns.fa
	#bwa mem -t 16 dbg.cns.fa sr.1.fa sr.2.fa | samtools sort -O SAM | ./wtpoa-cns -t 16 -x sam-sr -d dbg.cns.fa -i - -fo dbg.srp.fa
	exit 7
fi
