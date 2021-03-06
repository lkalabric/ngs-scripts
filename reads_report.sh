#!/bin/bash

# script: reads_report.sh
# autor: Luciano Kalabric <luciano.kalabric@fiocruz.br>
# instituição: Oswaldo Cruz Foundation, Gonçalo Moniz Institute, Bahia, Brazil
# objetivo: relatório do número de reads em cada passo de cada workflow
# criação: 03 DEZ 2021
# ultima atualização: 03 DEZ 2021
# atualização: revisão do script

# Valiação da entrada de dados na linha de comando
if [[ $# -ne 2 ]]; then
	echo "Falta o nome da biblioteca_model e/ou do barcodeXX!"
	echo "Sintáxe: reads_report.sh <BIBLIOTECA_MODEL> <BARCODE>"
	echo "Exemplo: reads_report.sh DENV_FTA_1_hac barcode01"
	exit 0
fi

RUNNAME=$1
BARCODE=$2

RESULTSDIR="${HOME}/ngs-analysis/${RUNNAME}"
DEMUX_CATDIR="${RESULTSDIR}/DEMUX_CAT"

echo "=== reads_report output ==="
echo "All reads:" $(grep -o "runid" $(find -H ${RESULTSDIR}/BASECALL -name *.fastq) | wc -l)
echo "Pass reads:" $(grep -o "runid" $(find -H ${RESULTSDIR}/BASECALL/pass -name *.fastq) | wc -l)
echo "Demux:"
for i in $(find ${DEMUX_CATDIR} -mindepth 1 -type f -name "barcode*" -exec basename {} \; | sort); do
    echo "$i:" $(fastq_summary_v2.sh "${DEMUX_CATDIR}/${i}")
done

echo -e "\nResultados ${BARCODE} no WF2"
  echo "Cutadapt:" $(fastq_summary_v2.sh ${RESULTSDIR}/wf2/CUTADAPT/${BARCODE}.fastq)
  echo "Nanofilt:" $(fastq_summary_v2.sh ${RESULTSDIR}/wf2/NANOFILT/${BARCODE}.fastq)
  echo "Prinseq:" $(fastq_summary_v2.sh ${RESULTSDIR}/wf2/PRINSEQ/${BARCODE}.good.fastq)
  echo "Blast:" $(wc -l ${RESULTSDIR}/wf2/BLAST/${BARCODE}.blastn)

echo -e "\nResultados ${BARCODE} no WF31"
  echo "Nanofilt:" $(fastq_summary_v2.sh ${RESULTSDIR}/wf31/NANOFILT/${BARCODE}.fastq)
  echo "Prinseq:" $(fastq_summary_v2.sh ${RESULTSDIR}/wf31/PRINSEQ/${BARCODE}.good.fastq)
  echo "Kraken2:"
  echo "root - " $(grep "root" ${RESULTSDIR}/wf31/READS_LEVEL/${BARCODE}_report.txt | cut -f 2)
  echo "Viruses - " $(grep "Viruses" ${RESULTSDIR}/wf31/READS_LEVEL/${BARCODE}_report.txt | cut -f 2)
