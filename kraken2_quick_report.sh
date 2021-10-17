#!/bin/bash

# script: kraken2_quick_report.sh
# autor: Luciano Kalabric <luciano.kalabric@fiocruz.br>
# instituição: Oswaldo Cruz Foundation, Gonçalo Moniz Institute, Bahia, Brazil
# objetivo: relatório resumido dos resultados da classificação taxonômica pelo kraken2
# criação: 25 AGO 2021
# ultima atualização: 17 OUT 2021
# atualização: revisão do script
# requisito: arquivo taxin que contém a lista de taxons de interesse

# Valiação da entrada de dados na linha de comando
if [[ $# -ne 2 ]]; then
	echo "Faltando algum parâmetro!"
	echo "Sintáxe: ./kraken2_quick_report.sh <BIBLIOTECA_MODEL> <BARCODE>"
	echo "Exemplo: ./kraken2_quick_report.sh DENV_FTA_1_hac barcode01"
	exit 0
fi

# Atualizar na medida do necessário
RUNNAME=$1
WF=31
BARCODE=$2
RESULTSDIR="$HOME/ngs-analysis/$RUNNAME/wf$WF"
READSLEVELDIR="${RESULTSDIR}/READS_LEVEL"

while read -r line ; do
	count=$(agrep -q -w "$line" ${READSLEVELDIR}/${BARCODE}_report.txt | cut -f 2)
	echo "$line - $count"
done < <(cat /home/brazil1/data/REFSEQ/taxin | tr '\t' ';')
